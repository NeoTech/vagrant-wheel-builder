# build-sageattention.ps1
# Build SageAttention wheel

$ErrorActionPreference = "Stop"

# Load common functions
. "C:\output\build-common.ps1"

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Building: SageAttention" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

# Initialize environment
Initialize-BuildEnvironment
Install-Dependencies

# Package config
$pkgName = "sageattention"
$pkgRepo = "https://github.com/thu-ml/SageAttention.git"
$pkgTag = "v2.0.1"
$pkgBuildDir = Join-Path $buildRoot $pkgName

# SageAttention specific - PyTorch 2.8 only supports up to 8.9 for this package
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
    
    # Patch math.cuh for Windows compatibility (ushort -> unsigned short)
    $mathCuh = "csrc\math.cuh"
    if (Test-Path $mathCuh) {
        Write-Host "Patching math.cuh for Windows compatibility..." -ForegroundColor Yellow
        $content = Get-Content $mathCuh -Raw
        # Replace 'ushort' with 'unsigned short' (Windows doesn't have ushort typedef)
        $content = $content -replace '\bushort\b', 'unsigned short'
        Set-Content $mathCuh $content -NoNewline
    }
    
    # Install requirements if exists
    if (Test-Path "requirements.txt") {
        Write-Host "Installing package requirements..." -ForegroundColor Yellow
        & $pythonExe -m pip install -r requirements.txt
    }
    
    # Patch setup.py to reduce nvcc threads (prevents OOM)
    $setupPy = Get-Content "setup.py" -Raw
    if ($setupPy -match "--threads=\d+") {
        Write-Host "Patching setup.py to reduce nvcc threads..." -ForegroundColor Yellow
        $setupPy = $setupPy -replace "--threads=\d+", "--threads=1"
        Set-Content "setup.py" $setupPy
    }
    
    Write-Host "`nBuilding wheel..." -ForegroundColor Yellow
    & $pythonExe -m pip wheel --no-build-isolation --no-deps --wheel-dir $outputDir --verbose .
    
    if ($LASTEXITCODE -eq 0) {
        Write-Host "`nSUCCESS: SageAttention built successfully!" -ForegroundColor Green
    } else {
        Write-Host "`nFAILED: SageAttention build failed with exit code $LASTEXITCODE" -ForegroundColor Red
        exit 1
    }
    
    Pop-Location
    
} catch {
    Write-Host "ERROR: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

Show-BuildResult
