# build-flash-attention.ps1
# Build flash-attention wheel

$ErrorActionPreference = "Stop"

# Load common functions
. "C:\output\build-common.ps1"

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Building: flash-attention" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

# Initialize environment
Initialize-BuildEnvironment
Install-Dependencies

# Package config
$pkgName = "flash-attention"
$pkgRepo = "https://github.com/Dao-AILab/flash-attention.git"
$pkgTag = "v2.7.2"
$pkgBuildDir = Join-Path $buildRoot $pkgName

# Set flash-attention specific environment
$env:FLASH_ATTENTION_FORCE_BUILD = "TRUE"
$env:FLASH_ATTENTION_SKIP_CUDA_BUILD = "FALSE"
$env:TORCH_CUDA_ARCH_LIST = "8.6;8.9;10.0"  # RTX 30xx, 40xx, 50xx

try {
    Write-Host "`nCloning $pkgRepo (tag: $pkgTag)..." -ForegroundColor Yellow
    
    if (Test-Path $pkgBuildDir) {
        Remove-Item -Recurse -Force $pkgBuildDir
    }
    
    git clone --depth 1 --branch $pkgTag $pkgRepo $pkgBuildDir
    
    Push-Location $pkgBuildDir
    
    # Initialize submodules (cutlass)
    Write-Host "Initializing submodules..." -ForegroundColor Yellow
    git submodule update --init --recursive
    
    Write-Host "`nBuilding wheel (this may take 30-60 minutes)..." -ForegroundColor Yellow
    Write-Host "Progress: Watch for [X/85] showing files compiled" -ForegroundColor Cyan
    & $pythonExe -m pip wheel --no-build-isolation --no-deps --wheel-dir $outputDir --verbose .
    
    if ($LASTEXITCODE -eq 0) {
        Write-Host "`nSUCCESS: flash-attention built successfully!" -ForegroundColor Green
    } else {
        Write-Host "`nFAILED: flash-attention build failed with exit code $LASTEXITCODE" -ForegroundColor Red
        exit 1
    }
    
    Pop-Location
    
} catch {
    Write-Host "ERROR: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

Show-BuildResult
