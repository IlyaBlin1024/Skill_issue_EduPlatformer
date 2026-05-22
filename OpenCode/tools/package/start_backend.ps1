[CmdletBinding()]
param(
    [switch]$SkipPythonInstall
)

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$backendDir = Join-Path $root "backend"
$venvDir = Join-Path $root ".runtime\backend-venv"
$logDir = Join-Path $root "logs"

function Test-BackendHealth {
    try {
        $response = Invoke-WebRequest -Uri "http://127.0.0.1:8000/health" -UseBasicParsing -TimeoutSec 1
        return $response.StatusCode -eq 200
    } catch {
        return $false
    }
}

function Resolve-Python {
    $pyLauncher = Get-Command "py" -ErrorAction SilentlyContinue
    if ($pyLauncher) {
        return @($pyLauncher.Source, "-3")
    }
    foreach ($commandName in @("python", "python3")) {
        $command = Get-Command $commandName -ErrorAction SilentlyContinue
        if ($command) {
            return @($command.Source)
        }
    }
    if (-not $SkipPythonInstall) {
        $winget = Get-Command "winget" -ErrorAction SilentlyContinue
        if ($winget) {
            & $winget.Source install --id Python.Python.3.12 -e --silent --accept-package-agreements --accept-source-agreements --scope user
            $env:PATH = [System.Environment]::GetEnvironmentVariable("PATH", "Machine") + ";" + [System.Environment]::GetEnvironmentVariable("PATH", "User")
            $pyLauncher = Get-Command "py" -ErrorAction SilentlyContinue
            if ($pyLauncher) {
                return @($pyLauncher.Source, "-3")
            }
            foreach ($commandName in @("python", "python3")) {
                $command = Get-Command $commandName -ErrorAction SilentlyContinue
                if ($command) {
                    return @($command.Source)
                }
            }
        }
    }
    throw "Python was not found. Install Python 3.11+ or launch the game through SkillIssue.bat."
}

function Invoke-PythonCommand([string[]]$PythonCommand, [string[]]$Arguments) {
    $exe = $PythonCommand[0]
    $baseArgs = @()
    if ($PythonCommand.Count -gt 1) {
        $baseArgs = $PythonCommand[1..($PythonCommand.Count - 1)]
    }
    & $exe @baseArgs @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "Python command failed: $exe $($Arguments -join ' ')"
    }
}

function Test-PythonExecutable([string]$PythonPath) {
    if (-not (Test-Path -LiteralPath $PythonPath)) {
        return $false
    }
    try {
        & $PythonPath --version *> $null
        return $LASTEXITCODE -eq 0
    } catch {
        return $false
    }
}

function Reset-BrokenBackendVenv {
    $venvFull = [System.IO.Path]::GetFullPath($venvDir)
    $rootFull = ([System.IO.Path]::GetFullPath($root)).TrimEnd([System.IO.Path]::DirectorySeparatorChar) + [System.IO.Path]::DirectorySeparatorChar
    if (-not $venvFull.StartsWith($rootFull, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Refusing to remove venv outside release directory: $venvFull"
    }
    if (Test-Path -LiteralPath $venvDir) {
        Remove-Item -LiteralPath $venvDir -Recurse -Force
    }
}

if (Test-BackendHealth) {
    exit 0
}
if (-not (Test-Path -LiteralPath $backendDir)) {
    exit 0
}

$pythonCommand = Resolve-Python
$venvPython = Join-Path $venvDir "Scripts\python.exe"
if ((Test-Path -LiteralPath $venvPython) -and -not (Test-PythonExecutable $venvPython)) {
    Reset-BrokenBackendVenv
}
if (-not (Test-Path -LiteralPath $venvPython)) {
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $venvDir) | Out-Null
    Invoke-PythonCommand $pythonCommand @("-m", "venv", $venvDir)
}

& $venvPython -m pip install --disable-pip-version-check -r (Join-Path $backendDir "requirements.txt") *> $null
if ($LASTEXITCODE -ne 0) {
    throw "Failed to install backend dependencies."
}

New-Item -ItemType Directory -Force -Path $logDir | Out-Null
$stdoutLog = Join-Path $logDir "backend.out.log"
$stderrLog = Join-Path $logDir "backend.err.log"
Start-Process -FilePath $venvPython `
    -ArgumentList @("-m", "uvicorn", "app.main:app", "--host", "127.0.0.1", "--port", "8000") `
    -WorkingDirectory $backendDir `
    -WindowStyle Hidden `
    -RedirectStandardOutput $stdoutLog `
    -RedirectStandardError $stderrLog | Out-Null
