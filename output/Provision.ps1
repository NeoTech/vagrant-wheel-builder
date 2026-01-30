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

# Install CUDA Toolkit 12.8
Write-Host "Installing CUDA Toolkit 12.8 from local installer..." -ForegroundColor Green
$cudaInstaller = "C:\output\cuda_12.8.0_571.96_windows.exe"
if (Test-Path $cudaInstaller) {
    & $cudaInstaller -s nvcc_12.8 cuobjdump_12.8 nvprune_12.8 nvprof_12.8 cupti_12.8 cublas_12.8 cublas_dev_12.8 cudart_12.8 cufft_12.8 cufft_dev_12.8 curand_12.8 curand_dev_12.8 cusolver_12.8 cusolver_dev_12.8 cusparse_12.8 cusparse_dev_12.8 npp_12.8 npp_dev_12.8 nvrtc_12.8 nvrtc_dev_12.8 nvml_dev_12.8 nsight_nvtx_12.8
    if ($LASTEXITCODE -ne 0) {
        Write-Host "WARNING: CUDA installer returned exit code $LASTEXITCODE" -ForegroundColor Yellow
    }
} else {
    Write-Host "ERROR: CUDA installer not found at $cudaInstaller" -ForegroundColor Red
    Write-Host "Please download cuda_12.8.0_571.96_windows.exe to the output folder" -ForegroundColor Yellow
    exit 1
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

# Set environment variables permanently
[System.Environment]::SetEnvironmentVariable("CUDA_PATH", "C:\Program Files\NVIDIA GPU Computing Toolkit\CUDA\v12.8", [System.EnvironmentVariableTarget]::Machine)
[System.Environment]::SetEnvironmentVariable("CUDA_HOME", "C:\Program Files\NVIDIA GPU Computing Toolkit\CUDA\v12.8", [System.EnvironmentVariableTarget]::Machine)

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