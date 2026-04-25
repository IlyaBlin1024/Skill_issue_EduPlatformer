[CmdletBinding()]
param(
    [string]$DownloadUrl = "",
    [string]$ArchivePath = "",
    [string]$InstallDir = "",
    [switch]$NoShortcut,
    [switch]$NoLaunch
)

$ErrorActionPreference = "Stop"

function Resolve-InstallRoot {
    if ($InstallDir) {
        return [System.IO.Path]::GetFullPath($InstallDir)
    }
    return Join-Path $env:LOCALAPPDATA "Skill Issue"
}

function Resolve-ArchivePath {
    if ($ArchivePath) {
        return [System.IO.Path]::GetFullPath($ArchivePath)
    }
    $scriptRoot = Split-Path -Parent $MyInvocation.ScriptName
    $localArchive = Join-Path $scriptRoot "Skill-Issue-windows.zip"
    if (Test-Path -LiteralPath $localArchive) {
        return $localArchive
    }
    $downloadArchive = Join-Path $env:TEMP "Skill-Issue-windows.zip"
    if (-not $DownloadUrl) {
        throw "Skill-Issue-windows.zip was not found next to this installer. Pass -DownloadUrl or -ArchivePath."
    }
    Write-Host "Downloading Skill Issue package..."
    Invoke-WebRequest -Uri $DownloadUrl -OutFile $downloadArchive -UseBasicParsing
    return $downloadArchive
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
    $iconPath = Join-Path $WorkingDirectory "SkillIssue.exe"
    if (Test-Path -LiteralPath $iconPath) {
        $shortcut.IconLocation = $iconPath
    }
    $shortcut.Save()
}

$installRoot = Resolve-InstallRoot
$archive = Resolve-ArchivePath
$staging = Join-Path $env:TEMP ("Skill-Issue-install-" + [Guid]::NewGuid().ToString("N"))

Write-Host "Installing Skill Issue to: $installRoot"
if (Test-Path -LiteralPath $staging) {
    Remove-Item -LiteralPath $staging -Recurse -Force
}
New-Item -ItemType Directory -Force -Path $staging | Out-Null
New-Item -ItemType Directory -Force -Path $installRoot | Out-Null
Expand-Archive -LiteralPath $archive -DestinationPath $staging -Force
Copy-Item -Path (Join-Path $staging "*") -Destination $installRoot -Recurse -Force
Remove-Item -LiteralPath $staging -Recurse -Force

$launcher = Join-Path $installRoot "SkillIssue.bat"
if (-not (Test-Path -LiteralPath $launcher)) {
    throw "Skill Issue launcher was not found after install."
}

if (-not $NoShortcut) {
    New-DesktopShortcut $launcher $installRoot
}

if (-not $NoLaunch) {
    Write-Host "Starting Skill Issue..."
    Start-Process -FilePath $launcher -WorkingDirectory $installRoot
} else {
    Write-Host "Install complete. Launch skipped by -NoLaunch."
}
