# provision.ps1

$ErrorActionPreference = "Stop"

Write-Host "Setting up Windows build environment..." -ForegroundColor Cyan

# Install Chocolatey
Set-ExecutionPolicy Bypass -Scope Process -Force
[System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072
iex ((New-Object System.Net.WebClient).DownloadString('https://community.chocolatey.org/install.ps1'))

$env:ChocolateyInstall = Convert-Path "$((Get-Command choco).Path)\..\.."
Import-Module "$env:ChocolateyInstall\helpers\chocolateyProfile.psm1"
refreshenv

# Install Visual Studio Build Tools (CLI only)
Write-Host "Installing Visual Studio Build Tools (CLI only)..." -ForegroundColor Green
choco install -y visualstudio2022buildtools `
    --package-parameters "--quiet --wait --norestart --nocache `
    --add Microsoft.VisualStudio.Workload.VCTools `
    --add Microsoft.VisualStudio.Component.VC.Tools.x86.x64 `
    --add Microsoft.VisualStudio.Component.VC.ATL `
    --add Microsoft.VisualStudio.Component.VC.ATLMFC"

# Install Windows 10 SDK separately (includes ucrt with corecrt.h)
Write-Host "Installing Windows 10 SDK..." -ForegroundColor Green
choco install -y windows-sdk-10-version-2004-all

# Read CUDA version from build-config.toml
$configPath = "C:\output\build-config.toml"
$cudaVersion = "12.8"  # Default fallback

if (Test-Path $configPath) {
    $content = Get-Content $configPath -Raw
    if ($content -match '(?m)^\s*cuda_version\s*=\s*["'']([^"'']+)["'']') {
        $cudaVersion = $matches[1]
        Write-Host "Read CUDA version from config: $cudaVersion" -ForegroundColor Green
    }
}

# Install CUDA Toolkit from local installer
Write-Host "Installing CUDA Toolkit $cudaVersion from local installer..." -ForegroundColor Green

# Find matching CUDA installer(s) - match major.minor version
$cudaInstallers = Get-ChildItem -Path "C:\output" -Filter "cuda_$cudaVersion*.exe" -ErrorAction SilentlyContinue
if (-not $cudaInstallers -or $cudaInstallers.Count -eq 0) {
    Write-Host "ERROR: No CUDA installer matching 'cuda_$cudaVersion*.exe' found in C:\output" -ForegroundColor Red
    Write-Host "Please run download-cuda.ps1 on the host before 'vagrant up'" -ForegroundColor Yellow
    Write-Host "  .\download-cuda.ps1         # Download via Chocolatey" -ForegroundColor Yellow
    Write-Host "  .\download-cuda.ps1 -Direct # Download from NVIDIA directly" -ForegroundColor Yellow
    exit 1
}

# Use the first matching installer (should typically only be one)
$cudaInstaller = $cudaInstallers[0].FullName
Write-Host "Using installer: $($cudaInstallers[0].Name)" -ForegroundColor Cyan

# Extract version components for component names (e.g., 12.8 -> nvcc_12.8)
$versionParts = $cudaVersion -split '\.'
$componentVersion = "$($versionParts[0]).$($versionParts[1])"

& $cudaInstaller -s "nvcc_$componentVersion" "cuobjdump_$componentVersion" "nvprune_$componentVersion" "nvprof_$componentVersion" "cupti_$componentVersion" "cublas_$componentVersion" "cublas_dev_$componentVersion" "cudart_$componentVersion" "cufft_$componentVersion" "cufft_dev_$componentVersion" "curand_$componentVersion" "curand_dev_$componentVersion" "cusolver_$componentVersion" "cusolver_dev_$componentVersion" "cusparse_$componentVersion" "cusparse_dev_$componentVersion" "npp_$componentVersion" "npp_dev_$componentVersion" "nvrtc_$componentVersion" "nvrtc_dev_$componentVersion" "nvml_dev_$componentVersion" "nsight_nvtx_$componentVersion"
if ($LASTEXITCODE -ne 0) {
    Write-Host "WARNING: CUDA installer returned exit code $LASTEXITCODE" -ForegroundColor Yellow
}

# Install Git (minimal)
choco install -y git --params "/GitOnlyOnPath /NoAutoCrlf"

# Install CMake and Ninja
choco install -y cmake ninja

# Install Python 3.12 specifically
Write-Host "Installing Python 3.12..." -ForegroundColor Green
choco install -y python312 --version=3.12.10

refreshenv

# Verify Python installation
$pythonExe = "C:\Python312\python.exe"
if (-not (Test-Path $pythonExe)) {
    Write-Host "ERROR: Python 3.12 not found at $pythonExe" -ForegroundColor Red
    exit 1
}

Write-Host "Python installed: $(& $pythonExe --version)" -ForegroundColor Green

# Install UV using Python
Write-Host "Installing UV package manager..." -ForegroundColor Green
& $pythonExe -m pip install --upgrade pip
& $pythonExe -m pip install uv

# Verify UV installation
$uvExe = "C:\Python312\Scripts\uv.exe"
if (-not (Test-Path $uvExe)) {
    Write-Host "ERROR: UV not found at $uvExe" -ForegroundColor Red
    exit 1
}

Write-Host "UV installed: $(& $uvExe --version)" -ForegroundColor Green

# Set environment variables permanently (use cudaVersion from earlier)
[System.Environment]::SetEnvironmentVariable("CUDA_PATH", "C:\Program Files\NVIDIA GPU Computing Toolkit\CUDA\v$cudaVersion", [System.EnvironmentVariableTarget]::Machine)
[System.Environment]::SetEnvironmentVariable("CUDA_HOME", "C:\Program Files\NVIDIA GPU Computing Toolkit\CUDA\v$cudaVersion", [System.EnvironmentVariableTarget]::Machine)

# Find and set Windows SDK path
$sdkBase = "C:\Program Files (x86)\Windows Kits\10"
if (Test-Path "$sdkBase\Include") {
    $sdkVersions = Get-ChildItem "$sdkBase\Include" -Directory | 
        Where-Object { $_.Name -match "^10\.0\.\d+\.\d+$" } |
        Sort-Object Name -Descending
    if ($sdkVersions.Count -gt 0) {
        $sdkVersion = $sdkVersions[0].Name
        Write-Host "Found Windows SDK version: $sdkVersion" -ForegroundColor Green
        [System.Environment]::SetEnvironmentVariable("WindowsSdkDir", $sdkBase, [System.EnvironmentVariableTarget]::Machine)
        [System.Environment]::SetEnvironmentVariable("WindowsSDKVersion", "$sdkVersion\", [System.EnvironmentVariableTarget]::Machine)
        
        # Verify corecrt.h exists
        $corecrtPath = "$sdkBase\Include\$sdkVersion\ucrt\corecrt.h"
        if (Test-Path $corecrtPath) {
            Write-Host "Verified corecrt.h exists at: $corecrtPath" -ForegroundColor Green
        } else {
            Write-Host "WARNING: corecrt.h not found at $corecrtPath" -ForegroundColor Yellow
        }
    } else {
        Write-Host "WARNING: No Windows SDK versions found" -ForegroundColor Yellow
    }
} else {
    Write-Host "WARNING: Windows SDK not found at $sdkBase" -ForegroundColor Yellow
}

Write-Host "Provisioning complete!" -ForegroundColor Green
Write-Host "Python: $(& $pythonExe --version)" -ForegroundColor Cyan
Write-Host "UV: $(& $uvExe --version)" -ForegroundColor Cyan