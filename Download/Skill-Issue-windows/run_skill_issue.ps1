[CmdletBinding()]
param(
    [switch]$NoBackend,
    [switch]$SkipPythonInstall
)

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$gameExe = Join-Path $root "SkillIssue.exe"
$backendDir = Join-Path $root "backend"
$venvDir = Join-Path $root ".runtime\backend-venv"
$logDir = Join-Path $root "logs"
$envFile = Join-Path $backendDir ".env"
$envExample = Join-Path $backendDir ".env.example"
$backendProcess = $null
$startedBackend = $false

function Write-SkillIssueBanner([string]$Message) {
    Write-Host ""
    Write-Host "========================================" -ForegroundColor DarkYellow
    Write-Host "              SKILL ISSUE               " -ForegroundColor Yellow
    Write-Host "========================================" -ForegroundColor DarkYellow
    Write-Host $Message -ForegroundColor Cyan
    Write-Host ""
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
        Install-PythonRuntime
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
    throw "Python was not found. Install Python 3.11+ or run with an already active backend."
}

function Install-PythonRuntime {
    $winget = Get-Command "winget" -ErrorAction SilentlyContinue
    if (-not $winget) {
        return
    }
    Write-Host "Python was not found. Installing Python 3.12 with winget..."
    & $winget.Source install --id Python.Python.3.12 -e --silent --accept-package-agreements --accept-source-agreements --scope user
    if ($LASTEXITCODE -ne 0) {
        Write-Warning "winget could not install Python automatically."
    }
    $env:PATH = [System.Environment]::GetEnvironmentVariable("PATH", "Machine") + ";" + [System.Environment]::GetEnvironmentVariable("PATH", "User")
}

function Invoke-PythonCommand([string[]]$PythonCommand, [string[]]$Arguments, [string]$WorkingDirectory) {
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
        Write-Host "Removing broken backend runtime venv..."
        Remove-Item -LiteralPath $venvDir -Recurse -Force
    }
}

function Test-BackendHealth {
    try {
        $response = Invoke-WebRequest -Uri "http://127.0.0.1:8000/health" -UseBasicParsing -TimeoutSec 1
        return $response.StatusCode -eq 200
    } catch {
        return $false
    }
}

if (-not (Test-Path -LiteralPath $gameExe)) {
    throw "SkillIssue.exe was not found next to this launcher."
}

try {
    Write-SkillIssueBanner "Preparing local backend and game launcher."
    if (-not $NoBackend) {
        if (Test-BackendHealth) {
            Write-Host "Backend is already running on http://127.0.0.1:8000"
        } else {
            if (-not (Test-Path -LiteralPath $envFile) -and (Test-Path -LiteralPath $envExample)) {
                Write-Host "backend\.env is optional. Enter the Hugging Face token in the game Settings screen."
            }
            $pythonCommand = Resolve-Python
            $venvPython = Join-Path $venvDir "Scripts\python.exe"
            if ((Test-Path -LiteralPath $venvPython) -and -not (Test-PythonExecutable $venvPython)) {
                Reset-BrokenBackendVenv
            }
            if (-not (Test-Path -LiteralPath $venvPython)) {
                Write-Host "Creating backend runtime venv..."
                New-Item -ItemType Directory -Force -Path (Split-Path -Parent $venvDir) | Out-Null
                Invoke-PythonCommand $pythonCommand @("-m", "venv", $venvDir) $root
            }

            Write-Host "Installing backend dependencies..."
            & $venvPython -m pip install --disable-pip-version-check -r (Join-Path $backendDir "requirements.txt")
            if ($LASTEXITCODE -ne 0) {
                throw "Failed to install backend dependencies."
            }

            New-Item -ItemType Directory -Force -Path $logDir | Out-Null
            $stdoutLog = Join-Path $logDir "backend.out.log"
            $stderrLog = Join-Path $logDir "backend.err.log"
            Write-Host "Starting backend..."
            $backendProcess = Start-Process -FilePath $venvPython `
                -ArgumentList @("-m", "uvicorn", "app.main:app", "--host", "127.0.0.1", "--port", "8000") `
                -WorkingDirectory $backendDir `
                -PassThru `
                -WindowStyle Hidden `
                -RedirectStandardOutput $stdoutLog `
                -RedirectStandardError $stderrLog
            $startedBackend = $true

            $ready = $false
            for ($i = 0; $i -lt 30; $i++) {
                Start-Sleep -Milliseconds 500
                if (Test-BackendHealth) {
                    $ready = $true
                    break
                }
            }
            if (-not $ready) {
                throw "Backend did not become ready. See logs\backend.err.log."
            }
        }
    }

    Write-Host "Starting Skill Issue..."
    Start-Process -FilePath $gameExe -WorkingDirectory $root -Wait
} finally {
    if ($startedBackend -and $backendProcess -and -not $backendProcess.HasExited) {
        Write-Host "Stopping backend..."
        Stop-Process -Id $backendProcess.Id -Force -ErrorAction SilentlyContinue
    }
}
