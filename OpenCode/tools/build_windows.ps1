[CmdletBinding()]
param(
    [string]$GodotExe = "",
    [string]$OutputRoot = "",
    [switch]$CopyToDownloads,
    [switch]$SkipExport,
    [switch]$SkipTemplateInstall,
    [switch]$NoArchive
)

$ErrorActionPreference = "Stop"

function Get-FullPath([string]$Path) {
    return [System.IO.Path]::GetFullPath($Path)
}

function Assert-ChildPath([string]$Child, [string]$Parent) {
    $childFull = Get-FullPath $Child
    $parentFull = (Get-FullPath $Parent).TrimEnd([System.IO.Path]::DirectorySeparatorChar) + [System.IO.Path]::DirectorySeparatorChar
    if (-not $childFull.StartsWith($parentFull, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Refusing to operate outside build directory: $childFull"
    }
}

function Resolve-GodotExecutable([string]$ExplicitPath) {
    if ($ExplicitPath) {
        if (Test-Path -LiteralPath $ExplicitPath) {
            return (Resolve-Path -LiteralPath $ExplicitPath).Path
        }
        throw "Godot executable was not found at: $ExplicitPath"
    }

    if ($env:GODOT_EXE -and (Test-Path -LiteralPath $env:GODOT_EXE)) {
        return (Resolve-Path -LiteralPath $env:GODOT_EXE).Path
    }

    foreach ($commandName in @("godot", "godot4", "Godot")) {
        $command = Get-Command $commandName -ErrorAction SilentlyContinue
        if ($command) {
            return $command.Source
        }
    }

    $runningGodot = Get-Process -ErrorAction SilentlyContinue |
        Where-Object { $_.ProcessName -like "Godot*" -and $_.Path -and (Test-Path -LiteralPath $_.Path) } |
        Select-Object -First 1
    if ($runningGodot) {
        return $runningGodot.Path
    }

    $candidatePatterns = @(
        (Join-Path $env:LOCALAPPDATA "Programs\Godot\Godot*.exe"),
        (Join-Path $env:ProgramFiles "Godot\Godot*.exe"),
        (Join-Path $env:ProgramFiles "Godot*\Godot*.exe"),
        (Join-Path ${env:ProgramFiles(x86)} "Godot\Godot*.exe"),
        (Join-Path $env:USERPROFILE "Downloads\Godot*.exe"),
        (Join-Path $env:USERPROFILE "Desktop\Godot*.exe")
    )

    foreach ($pattern in $candidatePatterns) {
        if (-not $pattern) {
            continue
        }
        $match = Get-ChildItem -Path $pattern -File -ErrorAction SilentlyContinue |
            Sort-Object LastWriteTime -Descending |
            Select-Object -First 1
        if ($match) {
            return $match.FullName
        }
    }

    throw "Godot executable was not found. Pass -GodotExe `"C:\Path\To\Godot.exe`" or set GODOT_EXE."
}

function Get-GodotVersionInfo([string]$GodotPath) {
    $versionText = ""
    try {
        $versionOutput = & $GodotPath --version 2>&1
        if ($versionOutput) {
            $versionText = ($versionOutput | Select-Object -First 1).ToString()
        }
    } catch {
        $versionText = ""
    }

    $searchText = "$versionText $GodotPath"
    if ($searchText -match "(\d+\.\d+(?:\.\d+)?)-(stable|rc\d+|beta\d+|alpha\d+)") {
        $versionNumber = $Matches[1]
        $releaseKind = $Matches[2]
        return @{
            ReleaseTag = "$versionNumber-$releaseKind"
            TemplateFolder = "$versionNumber.$releaseKind"
        }
    }

    throw "Could not detect Godot version from: $GodotPath"
}

function Ensure-GodotExportTemplates([string]$GodotPath, [string]$CacheRoot) {
    $versionInfo = Get-GodotVersionInfo $GodotPath
    $templateRoot = Join-Path $env:APPDATA ("Godot\export_templates\" + $versionInfo.TemplateFolder)
    $windowsTemplate = Get-ChildItem -LiteralPath $templateRoot -Filter "windows_release*.exe" -File -ErrorAction SilentlyContinue |
        Select-Object -First 1
    if ($windowsTemplate) {
        Write-Host "Export templates: $templateRoot"
        return
    }

    Write-Host "Windows export templates are missing. Installing automatically..."
    New-Item -ItemType Directory -Force -Path $CacheRoot | Out-Null
    New-Item -ItemType Directory -Force -Path $templateRoot | Out-Null

    $archiveName = "Godot_v$($versionInfo.ReleaseTag)_export_templates.tpz"
    $downloadUrl = "https://github.com/godotengine/godot/releases/download/$($versionInfo.ReleaseTag)/$archiveName"
    $tpzPath = Join-Path $CacheRoot $archiveName
    $zipPath = Join-Path $CacheRoot ($archiveName + ".zip")
    $extractDir = Join-Path $CacheRoot "export_templates_extract"

    if (-not (Test-Path -LiteralPath $tpzPath)) {
        Write-Host "Downloading: $downloadUrl"
        Invoke-WebRequest -Uri $downloadUrl -OutFile $tpzPath -UseBasicParsing
    }

    if (Test-Path -LiteralPath $extractDir) {
        Remove-Item -LiteralPath $extractDir -Recurse -Force
    }
    New-Item -ItemType Directory -Force -Path $extractDir | Out-Null
    Copy-Item -LiteralPath $tpzPath -Destination $zipPath -Force
    Expand-Archive -LiteralPath $zipPath -DestinationPath $extractDir -Force

    $innerTemplates = Join-Path $extractDir "templates"
    if (-not (Test-Path -LiteralPath $innerTemplates)) {
        throw "Downloaded export templates archive has unexpected structure."
    }

    Copy-Item -Path (Join-Path $innerTemplates "*") -Destination $templateRoot -Recurse -Force
    Write-Host "Installed export templates to: $templateRoot"
}

function Copy-ReleaseFile([string]$SourcePath, [string]$DestinationPath, [bool]$AllowLockedExisting = $false) {
    try {
        Copy-Item -LiteralPath $SourcePath -Destination $DestinationPath -Force
    } catch {
        if ($AllowLockedExisting -and (Test-Path -LiteralPath $DestinationPath)) {
            Write-Warning "Could not overwrite locked file, keeping existing copy: $DestinationPath"
            return
        }
        throw
    }
}

function Remove-BuildDirectory([string]$Path, [string]$Parent) {
    Assert-ChildPath $Path $Parent
    if (-not (Test-Path -LiteralPath $Path)) {
        return
    }

    Get-ChildItem -LiteralPath $Path -Recurse -Force -ErrorAction SilentlyContinue | ForEach-Object {
        try {
            $_.Attributes = [System.IO.FileAttributes]::Normal
        } catch {
            # Some runtime files can be released a moment after the backend exits.
        }
    }

    $lastError = $null
    for ($attempt = 1; $attempt -le 6; $attempt++) {
        try {
            Remove-Item -LiteralPath $Path -Recurse -Force -ErrorAction Stop
            return
        } catch {
            $lastError = $_
            Start-Sleep -Milliseconds (250 * $attempt)
        }
    }

    $items = Get-ChildItem -LiteralPath $Path -Recurse -Force -ErrorAction SilentlyContinue |
        Sort-Object { $_.FullName.Length } -Descending
    foreach ($item in $items) {
        for ($attempt = 1; $attempt -le 5; $attempt++) {
            try {
                $item.Attributes = [System.IO.FileAttributes]::Normal
                Remove-Item -LiteralPath $item.FullName -Recurse -Force -ErrorAction Stop
                break
            } catch {
                $lastError = $_
                Start-Sleep -Milliseconds (180 * $attempt)
            }
        }
    }

    $remaining = @(Get-ChildItem -LiteralPath $Path -Force -ErrorAction SilentlyContinue)
    if ($remaining.Count -gt 0) {
        throw $lastError
    }
}

$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$repoRoot = Get-FullPath (Join-Path $scriptRoot "..")
$godotProject = Join-Path $repoRoot "godot"
$backendProject = Join-Path $repoRoot "backend"
$distRoot = if ($OutputRoot) { Get-FullPath $OutputRoot } else { Get-FullPath (Join-Path $repoRoot "dist") }
$packageDir = Get-FullPath (Join-Path $distRoot "Skill-Issue-windows")
$gameExe = Join-Path $packageDir "SkillIssue.exe"
$archivePath = Join-Path $distRoot "Skill-Issue-windows.zip"
$cacheRoot = Join-Path $distRoot ".cache"
$installerPs1 = Join-Path $distRoot "Install-And-Run-Skill-Issue.ps1"
$installerBat = Join-Path $distRoot "Install-And-Run-Skill-Issue.bat"

Write-Host "Skill Issue build started"
Write-Host "Repository: $repoRoot"
Write-Host "Output:     $packageDir"

New-Item -ItemType Directory -Force -Path $distRoot | Out-Null
Assert-ChildPath $packageDir $distRoot
if (Test-Path -LiteralPath $packageDir) {
    Remove-BuildDirectory $packageDir $distRoot
}
New-Item -ItemType Directory -Force -Path $packageDir | Out-Null

if (-not $SkipExport) {
    $godot = Resolve-GodotExecutable $GodotExe
    Write-Host "Godot:      $godot"
    if (-not $SkipTemplateInstall) {
        Ensure-GodotExportTemplates $godot $cacheRoot
    }
    Write-Host "Exporting Windows Desktop preset..."
    & $godot --headless --path $godotProject --export-release "Windows Desktop" $gameExe
    $godotExitCode = if ($null -eq $LASTEXITCODE) { 0 } else { [int]$LASTEXITCODE }
    $exportWaitDeadline = (Get-Date).AddSeconds(30)
    while (-not (Test-Path -LiteralPath $gameExe) -and (Get-Date) -lt $exportWaitDeadline) {
        Start-Sleep -Milliseconds 250
    }
    if ($godotExitCode -ne 0) {
        if (Test-Path -LiteralPath $gameExe) {
            Write-Warning "Godot export returned exit code $godotExitCode, but SkillIssue.exe was created. Continuing packaging."
        } else {
            throw "Godot export failed. Check that Windows export templates are installed for your Godot version."
        }
    }
    if (-not (Test-Path -LiteralPath $gameExe)) {
        throw "Godot export finished, but SkillIssue.exe was not created."
    }
} else {
    Write-Host "Skipping Godot export by request."
    if (Test-Path -LiteralPath $archivePath) {
        Write-Host "Restoring existing exported game from: $archivePath"
        Expand-Archive -LiteralPath $archivePath -DestinationPath $packageDir -Force
    }
    if (-not (Test-Path -LiteralPath $gameExe)) {
        throw "SkipExport needs an existing exported SkillIssue.exe. Run a full build with Godot once, or keep Skill-Issue-windows.zip in dist."
    }
}

Write-Host "Packaging backend..."
$backendTarget = Join-Path $packageDir "backend"
New-Item -ItemType Directory -Force -Path $backendTarget | Out-Null
Copy-Item -LiteralPath (Join-Path $backendProject "app") -Destination $backendTarget -Recurse -Force
Copy-Item -LiteralPath (Join-Path $backendProject "requirements.txt") -Destination $backendTarget -Force
if (Test-Path -LiteralPath (Join-Path $backendProject ".env.example")) {
    Copy-Item -LiteralPath (Join-Path $backendProject ".env.example") -Destination $backendTarget -Force
}
New-Item -ItemType Directory -Force -Path (Join-Path $backendTarget "data") | Out-Null
Get-ChildItem -LiteralPath $backendTarget -Recurse -Directory -Filter "__pycache__" -ErrorAction SilentlyContinue |
    Remove-Item -Recurse -Force
Get-ChildItem -LiteralPath $backendTarget -Recurse -File -Filter "*.pyc" -ErrorAction SilentlyContinue |
    Remove-Item -Force

Write-Host "Copying launchers..."
Copy-Item -LiteralPath (Join-Path $scriptRoot "package\SkillIssue.bat") -Destination $packageDir -Force
Copy-Item -LiteralPath (Join-Path $scriptRoot "package\run_skill_issue.ps1") -Destination $packageDir -Force
Copy-Item -LiteralPath (Join-Path $scriptRoot "package\start_backend.ps1") -Destination $packageDir -Force
Copy-Item -LiteralPath (Join-Path $scriptRoot "package\README_RELEASE.txt") -Destination $packageDir -Force
if (Test-Path -LiteralPath (Join-Path $godotProject "icon.ico")) {
    Copy-Item -LiteralPath (Join-Path $godotProject "icon.ico") -Destination (Join-Path $packageDir "SkillIssue.ico") -Force
}
if (Test-Path -LiteralPath (Join-Path $godotProject "icon.png")) {
    Copy-Item -LiteralPath (Join-Path $godotProject "icon.png") -Destination (Join-Path $packageDir "SkillIssue.png") -Force
}

$versionText = @(
    "Skill Issue local build",
    "Built at: $(Get-Date -Format s)",
    "Repository: $repoRoot"
)
Set-Content -LiteralPath (Join-Path $packageDir "VERSION.txt") -Value $versionText -Encoding UTF8

if (-not $NoArchive) {
    if (Test-Path -LiteralPath $archivePath) {
        Remove-Item -LiteralPath $archivePath -Force
    }
    Write-Host "Creating archive: $archivePath"
    Compress-Archive -Path (Join-Path $packageDir "*") -DestinationPath $archivePath -Force

    if ($CopyToDownloads) {
        $downloadsDir = Join-Path $env:USERPROFILE "Downloads"
        if (-not (Test-Path -LiteralPath $downloadsDir)) {
            throw "Downloads directory was not found: $downloadsDir"
        }
        $downloadArchive = Join-Path $downloadsDir "Skill-Issue-windows.zip"
        Copy-Item -LiteralPath $archivePath -Destination $downloadArchive -Force
        Write-Host "Copied archive to: $downloadArchive"
    }
}

Write-Host "Preparing install-and-run launcher..."
Copy-ReleaseFile (Join-Path $scriptRoot "installer\Install-And-Run-Skill-Issue.ps1") $installerPs1 $true
Copy-ReleaseFile (Join-Path $scriptRoot "installer\Install-And-Run-Skill-Issue.bat") $installerBat $true
if ($CopyToDownloads) {
    $downloadsDir = Join-Path $env:USERPROFILE "Downloads"
    Copy-ReleaseFile $installerPs1 (Join-Path $downloadsDir "Install-And-Run-Skill-Issue.ps1") $true
    Copy-ReleaseFile $installerBat (Join-Path $downloadsDir "Install-And-Run-Skill-Issue.bat") $true
}

Write-Host "Build complete."
Write-Host "Package: $packageDir"
if (-not $NoArchive) {
    Write-Host "Archive: $archivePath"
}
Write-Host "Installer: $installerBat"
