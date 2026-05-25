[CmdletBinding()]
param(
    [string]$DownloadUrl = "",
    [string]$ArchivePath = "",
    [string]$InstallDir = "",
    [switch]$NoShortcut,
    [switch]$NoLaunch
)

$ErrorActionPreference = "Stop"
Add-Type -AssemblyName System.IO.Compression.FileSystem

function Write-SkillIssueBanner([string]$Message) {
    Write-Host ""
    Write-Host "========================================" -ForegroundColor DarkYellow
    Write-Host "              SKILL ISSUE               " -ForegroundColor Yellow
    Write-Host "========================================" -ForegroundColor DarkYellow
    Write-Host $Message -ForegroundColor Cyan
    Write-Host ""
}

function Resolve-InstallRoot {
    if ($InstallDir) {
        return [System.IO.Path]::GetFullPath($InstallDir)
    }
    return Join-Path $env:LOCALAPPDATA "Skill Issue"
}

function Test-GitLfsPointer([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path)) {
        return $false
    }
    try {
        $firstLine = Get-Content -LiteralPath $Path -TotalCount 1 -ErrorAction Stop
        return $firstLine -eq "version https://git-lfs.github.com/spec/v1"
    } catch {
        return $false
    }
}

function Test-ZipArchive([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path)) {
        return $false
    }
    if ((Get-Item -LiteralPath $Path).Length -lt 22) {
        return $false
    }
    if (Test-GitLfsPointer $Path) {
        return $false
    }
    $zip = $null
    try {
        $zip = [System.IO.Compression.ZipFile]::OpenRead($Path)
        return $true
    } catch {
        return $false
    } finally {
        if ($zip) {
            $zip.Dispose()
        }
    }
}

function Test-PackageDirectory([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path -PathType Container)) {
        return $false
    }
    $launcher = Join-Path $Path "SkillIssue.bat"
    $gameExe = Join-Path $Path "SkillIssue.exe"
    if (-not (Test-Path -LiteralPath $launcher) -or -not (Test-Path -LiteralPath $gameExe)) {
        return $false
    }
    if (Test-GitLfsPointer $launcher -or Test-GitLfsPointer $gameExe) {
        return $false
    }
    return (Get-Item -LiteralPath $gameExe).Length -gt 1048576
}

function Resolve-PackageSource {
    $scriptRoot = Split-Path -Parent $MyInvocation.ScriptName
    $localPackageDir = Join-Path $scriptRoot "Skill-Issue-windows"

    if ($ArchivePath) {
        $explicitArchive = [System.IO.Path]::GetFullPath($ArchivePath)
        if (-not (Test-ZipArchive $explicitArchive)) {
            throw "ArchivePath is not a valid zip archive: $explicitArchive"
        }
        return @{ Kind = "Archive"; Path = $explicitArchive }
    }

    $localArchive = Join-Path $scriptRoot "Skill-Issue-windows.zip"
    if (Test-Path -LiteralPath $localArchive) {
        if (Test-ZipArchive $localArchive) {
            return @{ Kind = "Archive"; Path = $localArchive }
        }
        if (Test-GitLfsPointer $localArchive) {
            Write-Warning "Skill-Issue-windows.zip is a Git LFS pointer, not the real archive."
        } else {
            Write-Warning "Skill-Issue-windows.zip is not a valid zip archive."
        }
        if (Test-PackageDirectory $localPackageDir) {
            Write-Warning "Using the unpacked Skill-Issue-windows folder next to the installer instead."
            return @{ Kind = "Directory"; Path = $localPackageDir }
        }
    }

    if (Test-PackageDirectory $localPackageDir) {
        return @{ Kind = "Directory"; Path = $localPackageDir }
    }

    $downloadArchive = Join-Path $env:TEMP "Skill-Issue-windows.zip"
    if (-not $DownloadUrl) {
        throw "Skill-Issue-windows.zip was not found next to this installer. Pass -DownloadUrl or -ArchivePath, or place the Skill-Issue-windows folder next to the installer."
    }
    Write-Host "Downloading Skill Issue package..."
    Invoke-WebRequest -Uri $DownloadUrl -OutFile $downloadArchive -UseBasicParsing
    if (-not (Test-ZipArchive $downloadArchive)) {
        if (Test-GitLfsPointer $downloadArchive) {
            throw "Downloaded file is a Git LFS pointer, not the real archive. Download the release asset or run git lfs pull."
        }
        throw "Downloaded file is not a valid zip archive: $downloadArchive"
    }
    return @{ Kind = "Archive"; Path = $downloadArchive }
}

function New-DesktopShortcut([string]$TargetPath, [string]$WorkingDirectory) {
    $desktop = [Environment]::GetFolderPath("Desktop")
    if (-not $desktop) {
        return
    }
    $shortcutPath = Join-Path $desktop "Skill Issue.lnk"
    $shell = New-Object -ComObject WScript.Shell
    $shortcut = $shell.CreateShortcut($shortcutPath)
    $shortcut.TargetPath = $TargetPath
    $shortcut.WorkingDirectory = $WorkingDirectory
    $shortcut.Description = "Launch Skill Issue"
    $iconPath = Join-Path $WorkingDirectory "SkillIssue.ico"
    if (-not (Test-Path -LiteralPath $iconPath)) {
        $iconPath = Join-Path $WorkingDirectory "SkillIssue.exe"
    }
    if (Test-Path -LiteralPath $iconPath) {
        $shortcut.IconLocation = $iconPath
    }
    $shortcut.Save()
}

$installRoot = Resolve-InstallRoot
$packageSource = Resolve-PackageSource
$staging = Join-Path $env:TEMP ("Skill-Issue-install-" + [Guid]::NewGuid().ToString("N"))

Write-SkillIssueBanner "Installing Skill Issue to: $installRoot"
if (Test-Path -LiteralPath $staging) {
    Remove-Item -LiteralPath $staging -Recurse -Force
}
New-Item -ItemType Directory -Force -Path $staging | Out-Null
New-Item -ItemType Directory -Force -Path $installRoot | Out-Null
if ($packageSource["Kind"] -eq "Archive") {
    Expand-Archive -LiteralPath $packageSource["Path"] -DestinationPath $staging -Force
} else {
    Copy-Item -Path (Join-Path $packageSource["Path"] "*") -Destination $staging -Recurse -Force
}
Copy-Item -Path (Join-Path $staging "*") -Destination $installRoot -Recurse -Force
Remove-Item -LiteralPath $staging -Recurse -Force

$launcher = Join-Path $installRoot "SkillIssue.bat"
if (-not (Test-Path -LiteralPath $launcher)) {
    throw "Skill Issue launcher was not found after install."
}

if (-not $NoShortcut) {
    New-DesktopShortcut $launcher $installRoot
    Write-Host "Desktop shortcut created." -ForegroundColor Green
}

if (-not $NoLaunch) {
    Write-Host "Starting Skill Issue..." -ForegroundColor Green
    Start-Process -FilePath $launcher -WorkingDirectory $installRoot
} else {
    Write-Host "Install complete. Launch skipped by -NoLaunch." -ForegroundColor Green
}
