[CmdletBinding()]
param(
    [switch]$SkipInstall,
    [switch]$SkipPythonInstall
)

$ErrorActionPreference = "Stop"
$backendRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$venvDir = Join-Path $backendRoot ".venv"
$venvPython = Join-Path $venvDir "Scripts\python.exe"
$requirements = Join-Path $backendRoot "requirements.txt"
$envFile = Join-Path $backendRoot ".env"
$envExample = Join-Path $backendRoot ".env.example"

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
    throw "Python 3.11+ was not found. Install Python or add it to PATH."
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

function Reset-BrokenVenv {
    $venvFull = [System.IO.Path]::GetFullPath($venvDir)
    $backendFull = ([System.IO.Path]::GetFullPath($backendRoot)).TrimEnd([System.IO.Path]::DirectorySeparatorChar) + [System.IO.Path]::DirectorySeparatorChar
    if (-not $venvFull.StartsWith($backendFull, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Refusing to remove venv outside backend directory: $venvFull"
    }
    if (Test-Path -LiteralPath $venvDir) {
        Write-Host "Removing broken backend venv..."
        Remove-Item -LiteralPath $venvDir -Recurse -Force
    }
}

Set-Location $backendRoot

if (-not (Test-Path -LiteralPath $envFile) -and (Test-Path -LiteralPath $envExample)) {
    Write-Host "backend\.env is optional. Enter the Hugging Face token in the game Settings screen."
}

if ((Test-Path -LiteralPath $venvPython) -and -not (Test-PythonExecutable $venvPython)) {
    Reset-BrokenVenv
}

if (-not (Test-Path -LiteralPath $venvPython)) {
    Write-Host "Creating backend venv..."
    $pythonCommand = Resolve-Python
    Invoke-PythonCommand $pythonCommand @("-m", "venv", $venvDir)
}

if (-not $SkipInstall) {
    Write-Host "Installing backend dependencies..."
    & $venvPython -m pip install --disable-pip-version-check -r $requirements
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to install backend dependencies."
    }
}

Write-Host "Starting backend on http://127.0.0.1:8000"
& $venvPython -m uvicorn app.main:app --reload --host 127.0.0.1 --port 8000
