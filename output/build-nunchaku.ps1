# build-nunchaku.ps1
# Build Nunchaku wheel

$ErrorActionPreference = "Stop"

# Load common functions
. "C:\output\build-common.ps1"

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Building: Nunchaku" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

# Initialize environment
Initialize-BuildEnvironment
Install-Dependencies

# Package config
$pkgName = "nunchaku"
$pkgRepo = "https://github.com/mit-han-lab/nunchaku.git"
$pkgTag = "v1.2.1"
$pkgBuildDir = Join-Path $buildRoot $pkgName

# Nunchaku uses NUNCHAKU_INSTALL_MODE=ALL to skip GPU detection and use hardcoded targets
# Default ALL mode builds for: 75, 80, 86, 89 (and 120a if nvcc 12.8+)
$env:NUNCHAKU_INSTALL_MODE = "ALL"
$env:TORCH_CUDA_ARCH_LIST = "8.6;8.9"  # RTX 30xx, 40xx

try {
    Write-Host "`nCloning $pkgRepo (tag: $pkgTag)..." -ForegroundColor Yellow
    
    if (Test-Path $pkgBuildDir) {
        Remove-Item -Recurse -Force $pkgBuildDir
    }
    
    git clone --recursive --depth 1 --branch $pkgTag $pkgRepo $pkgBuildDir
    
    Push-Location $pkgBuildDir
    
    # Initialize submodules
    Write-Host "Initializing submodules..." -ForegroundColor Yellow
    git submodule update --init --recursive
    
    # Check if NVTX headers exist, if not create stub
    $nvtxDir = "$env:CUDA_PATH\include\nvtx3"
    $nvtxHeader = "$nvtxDir\nvToolsExt.h"
    if (-not (Test-Path $nvtxHeader)) {
        Write-Host "NVTX headers not found at $nvtxHeader, creating stub..." -ForegroundColor Yellow
        New-Item -ItemType Directory -Force -Path $nvtxDir | Out-Null
        @"
#pragma once
// Minimal NVTX stub for build compatibility on Windows
#include <cstdint>
#define NVTX_VERSION 3
typedef void* nvtxDomainHandle_t;
typedef void* nvtxStringHandle_t;
typedef uint64_t nvtxRangeId_t;
inline void nvtxRangePushA(const char*) {}
inline void nvtxRangePop() {}
inline nvtxRangeId_t nvtxRangeStartA(const char*) { return 0; }
inline void nvtxRangeEnd(nvtxRangeId_t) {}
inline void nvtxMarkA(const char*) {}
#define nvtxRangePush nvtxRangePushA
#define nvtxRangeStart nvtxRangeStartA
#define nvtxMark nvtxMarkA
"@ | Set-Content $nvtxHeader -Encoding UTF8
        Write-Host "Created NVTX stub at $nvtxHeader" -ForegroundColor Green
    } else {
        Write-Host "NVTX headers found at $nvtxHeader" -ForegroundColor Green
    }
    
    # Install requirements if exists
    if (Test-Path "requirements.txt") {
        Write-Host "Installing package requirements..." -ForegroundColor Yellow
        & $pythonExe -m pip install -r requirements.txt
    }
    
    Write-Host "`nBuilding wheel..." -ForegroundColor Yellow
    & $pythonExe -m pip wheel --no-build-isolation --no-deps --wheel-dir $outputDir --verbose .
    
    if ($LASTEXITCODE -eq 0) {
        Write-Host "`nSUCCESS: Nunchaku built successfully!" -ForegroundColor Green
    } else {
        Write-Host "`nFAILED: Nunchaku build failed with exit code $LASTEXITCODE" -ForegroundColor Red
        exit 1
    }
    
    Pop-Location
    
} catch {
    Write-Host "ERROR: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

Show-BuildResult
