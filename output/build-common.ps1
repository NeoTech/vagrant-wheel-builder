# build-common.ps1
# Common setup for all CUDA wheel builds

$ErrorActionPreference = "Stop"

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "CUDA Wheel Builder - Common Setup" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

# Configuration
$script:pythonVersion = "312"
$script:cudaVersion = "12.8"
$script:torchVersion = "2.8.0"
$script:torchCuda = "cu128"

# Paths
$script:pythonExe = "C:\Python$pythonVersion\python.exe"
$script:uvExe = "C:\Python$pythonVersion\Scripts\uv.exe"
$script:buildRoot = "C:\build"
$script:outputDir = "C:\output\wheels"

function Initialize-BuildEnvironment {
    # Verify Python and UV exist
    if (-not (Test-Path $script:pythonExe)) {
        Write-Host "ERROR: Python not found at $script:pythonExe" -ForegroundColor Red
        exit 1
    }

    if (-not (Test-Path $script:uvExe)) {
        Write-Host "ERROR: UV not found at $script:uvExe" -ForegroundColor Red
        Write-Host "Installing UV..." -ForegroundColor Yellow
        & $script:pythonExe -m pip install uv
        if (-not (Test-Path $script:uvExe)) {
            Write-Host "ERROR: Failed to install UV" -ForegroundColor Red
            exit 1
        }
    }

    # Set up build environment
    Write-Host "`nSetting up build environment..." -ForegroundColor Green
    $vsPath = "C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools\VC\Auxiliary\Build\vcvars64.bat"

    if (Test-Path $vsPath) {
        $tempFile = [System.IO.Path]::GetTempFileName()
        # Run vcvars64.bat and capture environment - ignore stderr as vcvars often has spurious warnings
        $null = cmd /c "`"$vsPath`" >nul 2>&1 && set > `"$tempFile`""
        if (Test-Path $tempFile) {
            Get-Content $tempFile | ForEach-Object {
                if ($_ -match "^(.*?)=(.*)$") {
                    Set-Item -Path "env:\$($matches[1])" -Value $matches[2] -ErrorAction SilentlyContinue
                }
            }
            Remove-Item $tempFile -ErrorAction SilentlyContinue
            Write-Host "Visual Studio environment loaded successfully" -ForegroundColor Green
        } else {
            Write-Host "WARNING: Failed to capture VS environment" -ForegroundColor Yellow
        }
    } else {
        Write-Host "WARNING: Visual Studio Build Tools not found at $vsPath" -ForegroundColor Yellow
    }

    # Find and add Windows SDK paths - search for installed versions
    $winSdkBase = "C:\Program Files (x86)\Windows Kits\10"
    $sdkVersion = $null
    
    # Find the latest installed SDK version
    if (Test-Path "$winSdkBase\Include") {
        $sdkVersions = Get-ChildItem "$winSdkBase\Include" -Directory | 
            Where-Object { $_.Name -match "^10\.0\.\d+\.\d+$" } |
            Sort-Object Name -Descending
        if ($sdkVersions.Count -gt 0) {
            $sdkVersion = $sdkVersions[0].Name
            Write-Host "Found Windows SDK version: $sdkVersion" -ForegroundColor Green
        }
    }

    if ($sdkVersion) {
        $ucrtInclude = "$winSdkBase\Include\$sdkVersion\ucrt"
        $sharedInclude = "$winSdkBase\Include\$sdkVersion\shared"
        $umInclude = "$winSdkBase\Include\$sdkVersion\um"
        $ucrtLib = "$winSdkBase\Lib\$sdkVersion\ucrt\x64"
        $umLib = "$winSdkBase\Lib\$sdkVersion\um\x64"
        
        # Build include paths
        $sdkIncludes = @()
        if (Test-Path $ucrtInclude) { $sdkIncludes += $ucrtInclude }
        if (Test-Path $sharedInclude) { $sdkIncludes += $sharedInclude }
        if (Test-Path $umInclude) { $sdkIncludes += $umInclude }
        
        # Build lib paths
        $sdkLibs = @()
        if (Test-Path $ucrtLib) { $sdkLibs += $ucrtLib }
        if (Test-Path $umLib) { $sdkLibs += $umLib }
        
        # Prepend to INCLUDE and LIB
        if ($sdkIncludes.Count -gt 0) {
            $env:INCLUDE = ($sdkIncludes -join ";") + ";$env:INCLUDE"
            Write-Host "Added SDK include paths: $($sdkIncludes -join ', ')" -ForegroundColor Green
        }
        if ($sdkLibs.Count -gt 0) {
            $env:LIB = ($sdkLibs -join ";") + ";$env:LIB"
            Write-Host "Added SDK lib paths: $($sdkLibs -join ', ')" -ForegroundColor Green
        }
    } else {
        Write-Host "WARNING: Windows SDK not found in $winSdkBase" -ForegroundColor Yellow
    }
    
    # Verify corecrt.h is accessible
    $corecrtPath = Get-ChildItem -Path "C:\Program Files (x86)\Windows Kits\10\Include" -Recurse -Filter "corecrt.h" -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($corecrtPath) {
        Write-Host "Verified corecrt.h at: $($corecrtPath.FullName)" -ForegroundColor Green
    } else {
        Write-Host "ERROR: corecrt.h not found - Windows SDK may not be properly installed" -ForegroundColor Red
        Write-Host "Please ensure Windows 10 SDK is installed with Universal CRT" -ForegroundColor Yellow
    }

    $env:CUDA_PATH = "C:\Program Files\NVIDIA GPU Computing Toolkit\CUDA\v$script:cudaVersion"
    $env:CUDA_HOME = $env:CUDA_PATH
    $env:PATH = "$env:CUDA_PATH\bin;$env:CUDA_PATH\libnvvp;$env:PATH"
    $env:MAX_JOBS = "2"
    # TORCH_CUDA_ARCH_LIST is set per-package in individual build scripts
    $env:NVCC = "$env:CUDA_PATH\bin\nvcc.exe"
    $env:DISTUTILS_USE_SDK = "1"
    $env:FORCE_CUDA = "1"
    $env:NVCC_THREADS = "1"  # Keep low - kernels use lots of RAM

    # Verify NVCC
    if (-not (Test-Path "$env:CUDA_PATH\bin\nvcc.exe")) {
        Write-Host "ERROR: NVCC not found at $env:CUDA_PATH\bin\nvcc.exe" -ForegroundColor Red
        exit 1
    }

    # Create directories
    New-Item -ItemType Directory -Force -Path $script:buildRoot | Out-Null
    New-Item -ItemType Directory -Force -Path $script:outputDir | Out-Null

    # Verify tools
    Write-Host "`nVerifying build tools..." -ForegroundColor Green
    Write-Host "Python: $(& $script:pythonExe --version)"
    Write-Host "UV: $(& $script:uvExe --version)"
    Write-Host "CUDA: $env:CUDA_PATH"
    Write-Host "NVCC: $(& "$env:CUDA_PATH\bin\nvcc.exe" --version | Select-Object -Last 1)"
    
    # Debug: Show include paths
    Write-Host "`nINCLUDE paths:" -ForegroundColor Yellow
    $env:INCLUDE -split ";" | ForEach-Object { if ($_) { Write-Host "  $_" } }
}

function Install-Dependencies {
    # Install PyTorch
    Write-Host "`nInstalling PyTorch $script:torchVersion with CUDA $script:torchCuda..." -ForegroundColor Green
    & $script:uvExe pip install --system torch==$script:torchVersion --index-url https://download.pytorch.org/whl/$script:torchCuda

    if ($LASTEXITCODE -ne 0) {
        Write-Host "ERROR: Failed to install PyTorch" -ForegroundColor Red
        exit 1
    }

    # Install build dependencies
    Write-Host "`nInstalling build dependencies..." -ForegroundColor Green
    & $script:uvExe pip install --system numpy ninja packaging setuptools wheel build pybind11

    if ($LASTEXITCODE -ne 0) {
        Write-Host "ERROR: Failed to install build dependencies" -ForegroundColor Red
        exit 1
    }
}

function Show-BuildResult {
    Write-Host "`n========================================" -ForegroundColor Cyan
    Write-Host "Build Complete!" -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Cyan

    Write-Host "`nBuilt wheels:" -ForegroundColor Green
    $wheels = Get-ChildItem $script:outputDir\*.whl -ErrorAction SilentlyContinue
    if ($wheels) {
        foreach ($wheel in $wheels) {
            $sizeMB = [math]::Round($wheel.Length / 1MB, 2)
            Write-Host "  - $($wheel.Name) ($sizeMB MB)" -ForegroundColor White
        }
    } else {
        Write-Host "  No wheels found" -ForegroundColor Yellow
    }
}
