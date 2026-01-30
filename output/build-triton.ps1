# build-triton.ps1
# Build triton-windows wheel from source

$ErrorActionPreference = "Stop"

# Load common functions
. "C:\output\build-common.ps1"

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Building: Triton-Windows" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

# Initialize environment
Initialize-BuildEnvironment
Install-Dependencies

# Package config
$pkgName = "triton"
$pkgRepo = "https://github.com/woct0rdho/triton-windows.git"
$pkgBranch = "release/3.4.x-windows"  # Triton 3.4 for PyTorch 2.8
$pkgBuildDir = "C:\tb"  # Short path to avoid 260-char limit
$logFile = "C:\output\triton-build.log"

# ============================================
# INSTALL ALL BUILD DEPENDENCIES FIRST
# ============================================
Write-Host "`n=== Installing ALL Build Dependencies ===" -ForegroundColor Yellow

# From pyproject.toml: requires = ["setuptools>=40.8.0", "cmake>=3.20,<4.0", "ninja>=1.11.1,<1.13", "pybind11>=2.13.1"]
Write-Host "Installing build-system requirements from pyproject.toml..." -ForegroundColor Cyan
& $uvExe pip install --system --upgrade pip setuptools wheel
& $uvExe pip install --system "setuptools>=40.8.0" "cmake>=3.20,<4.0" "ninja>=1.11.1,<1.13" "pybind11>=2.13.1"

# SSL certificates for HTTPS downloads during build
Write-Host "Installing SSL certificates..." -ForegroundColor Cyan
& $uvExe pip install --system certifi
$certifiPath = & $pythonExe -c "import certifi; print(certifi.where())"
$env:SSL_CERT_FILE = $certifiPath
$env:REQUESTS_CA_BUNDLE = $certifiPath
Write-Host "  SSL_CERT_FILE = $certifiPath" -ForegroundColor Green

# Get cmake/ninja paths from pip packages
$cmakeBinDir = & $pythonExe -c "import cmake; print(cmake.CMAKE_BIN_DIR)"
$ninjaBinDir = & $pythonExe -c "import ninja; print(ninja.BIN_DIR)"
Write-Host "  CMake: $cmakeBinDir" -ForegroundColor Green
Write-Host "  Ninja: $ninjaBinDir" -ForegroundColor Green

# ============================================
# AUTO-DETECT MSVC AND SDK
# ============================================
Write-Host "`n=== Detecting Build Tools ===" -ForegroundColor Yellow

$msvcBase = "C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools\VC\Tools\MSVC"
$msvcVersions = Get-ChildItem $msvcBase -Directory -ErrorAction SilentlyContinue | Sort-Object Name -Descending
if ($msvcVersions.Count -eq 0) {
    Write-Host "ERROR: MSVC not found in $msvcBase" -ForegroundColor Red
    exit 1
}
$msvcVersion = $msvcVersions[0].Name
Write-Host "  MSVC: $msvcVersion" -ForegroundColor Green

$sdkBase = "C:\Program Files (x86)\Windows Kits\10"
$sdkVersions = Get-ChildItem "$sdkBase\Include" -Directory -ErrorAction SilentlyContinue | 
    Where-Object { $_.Name -match "^10\.0\.\d+\.\d+$" } | Sort-Object Name -Descending
if ($sdkVersions.Count -eq 0) {
    Write-Host "ERROR: Windows SDK not found" -ForegroundColor Red
    exit 1
}
$sdkVersion = $sdkVersions[0].Name
Write-Host "  Windows SDK: $sdkVersion" -ForegroundColor Green
Write-Host "  CUDA: $env:CUDA_PATH" -ForegroundColor Green

# ============================================
# SET UP ENVIRONMENT
# ============================================
Write-Host "`n=== Configuring Environment ===" -ForegroundColor Yellow

$msvcBin = "C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools\VC\Tools\MSVC\$msvcVersion\bin\Hostx64\x64"
$sdkBin = "C:\Program Files (x86)\Windows Kits\10\bin\$sdkVersion\x64"

$env:Path = @(
    $cmakeBinDir,
    $ninjaBinDir,
    $msvcBin,
    $sdkBin,
    "C:\Windows\System32",
    "C:\Python312",
    "C:\Python312\Scripts",
    "C:\Program Files\Git\cmd",
    "$env:CUDA_PATH\bin"
) -join ";"

$env:INCLUDE = @(
    "C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools\VC\Tools\MSVC\$msvcVersion\include",
    "C:\Program Files (x86)\Windows Kits\10\Include\$sdkVersion\shared",
    "C:\Program Files (x86)\Windows Kits\10\Include\$sdkVersion\ucrt",
    "C:\Program Files (x86)\Windows Kits\10\Include\$sdkVersion\um",
    "$env:CUDA_PATH\include"
) -join ";"

$env:LIB = @(
    "C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools\VC\Tools\MSVC\$msvcVersion\lib\x64",
    "C:\Program Files (x86)\Windows Kits\10\Lib\$sdkVersion\ucrt\x64",
    "C:\Program Files (x86)\Windows Kits\10\Lib\$sdkVersion\um\x64"
) -join ";"

# Triton build options
$env:TRITON_BUILD_PROTON = "0"
$env:TRITON_BUILD_UT = "0"
$env:TRITON_BUILD_BINARY = "0"

# Build parallelism (32GB RAM)
$env:MAX_JOBS = "3"
$env:CMAKE_BUILD_PARALLEL_LEVEL = "3"
$env:PYTHONUNBUFFERED = "1"

# Verify tools work
Write-Host "  cmake: $(cmake --version | Select-Object -First 1)" -ForegroundColor Green
Write-Host "  ninja: $(ninja --version)" -ForegroundColor Green
$clVersion = (cmd /c "cl.exe 2>&1" | Select-String 'Version' | Select-Object -First 1).ToString().Trim()
Write-Host "  cl.exe: $clVersion" -ForegroundColor Green

# ============================================
# CLONE AND BUILD
# ============================================
try {
    Write-Host "`n=== Preparing Build Directory ===" -ForegroundColor Yellow
    
    if (Test-Path $pkgBuildDir) {
        Remove-Item -Recurse -Force $pkgBuildDir
    }
    
    # Clean triton cache
    $tritonCache = "C:\Users\vagrant\.triton"
    if (Test-Path $tritonCache) {
        Remove-Item -Recurse -Force $tritonCache
    }
    
    Write-Host "Cloning $pkgRepo..." -ForegroundColor Cyan
    git clone --depth 1 --branch $pkgBranch $pkgRepo $pkgBuildDir
    if ($LASTEXITCODE -ne 0) { throw "Git clone failed" }
    
    Push-Location $pkgBuildDir
    
    Write-Host "`n=== Building Wheel ===" -ForegroundColor Yellow
    Write-Host "Log file: $logFile" -ForegroundColor Cyan
    Write-Host "This will download LLVM (~500MB) and take 30-60 minutes..." -ForegroundColor Cyan
    
    # UV doesn't have 'pip wheel' - use pip directly for wheel building
    cmd /c "$pythonExe -m pip wheel --no-build-isolation --no-deps --wheel-dir $outputDir -v . > $logFile 2>&1"
    $buildExitCode = $LASTEXITCODE
    
    Write-Host "`n--- Build Log (last 100 lines) ---" -ForegroundColor Cyan
    if (Test-Path $logFile) { Get-Content $logFile -Tail 100 }
    Write-Host "--- End of Log ---`n" -ForegroundColor Cyan
    
    if ($buildExitCode -eq 0) {
        Write-Host "`nSUCCESS: Triton-Windows built!" -ForegroundColor Green
    } else {
        Write-Host "`nFAILED: Exit code $buildExitCode" -ForegroundColor Red
        Write-Host "Check full log: $logFile" -ForegroundColor Yellow
        exit 1
    }
    
    Pop-Location
    
} catch {
    Write-Host "ERROR: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

Show-BuildResult
