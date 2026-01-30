# test-env.ps1
# Test that all build dependencies are installed correctly

$ErrorActionPreference = "Continue"
$failCount = 0

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Build Environment Test" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

# Test NVCC
Write-Host "`n[1/7] Testing NVCC..." -ForegroundColor Yellow
if (Test-Path "C:\Program Files\NVIDIA GPU Computing Toolkit\CUDA\v12.8\bin\nvcc.exe") {
    $nvccVersion = & "C:\Program Files\NVIDIA GPU Computing Toolkit\CUDA\v12.8\bin\nvcc.exe" --version 2>&1 | Select-Object -Last 1
    Write-Host "  OK - NVCC found: $nvccVersion" -ForegroundColor Green
} else {
    Write-Host "  FAIL - NVCC not found" -ForegroundColor Red
    $failCount++
}

# Test Python
Write-Host "`n[2/7] Testing Python..." -ForegroundColor Yellow
if (Test-Path "C:\Python312\python.exe") {
    $pyVersion = & "C:\Python312\python.exe" --version 2>&1
    Write-Host "  OK - $pyVersion" -ForegroundColor Green
} else {
    Write-Host "  FAIL - Python not found" -ForegroundColor Red
    $failCount++
}

# Test Python packages
Write-Host "`n[3/7] Testing Python packages..." -ForegroundColor Yellow
$packages = @("torch", "numpy", "ninja", "packaging", "setuptools", "wheel", "build", "pybind11")
foreach ($pkg in $packages) {
    $result = & "C:\Python312\python.exe" -c "import $pkg; print($pkg.__version__)" 2>&1
    if ($LASTEXITCODE -eq 0) {
        Write-Host "  OK - $pkg ($result)" -ForegroundColor Green
    } else {
        Write-Host "  FAIL - $pkg not installed" -ForegroundColor Red
        $failCount++
    }
}

# Test PyTorch CUDA
Write-Host "`n[4/7] Testing PyTorch CUDA support..." -ForegroundColor Yellow
$cudaTest = & "C:\Python312\python.exe" -c "import torch; print('CUDA available:', torch.cuda.is_available()); print('CUDA version:', torch.version.cuda if torch.cuda.is_available() else 'N/A')" 2>&1
Write-Host "  $cudaTest" -ForegroundColor $(if ($cudaTest -match "True") { "Green" } else { "Yellow" })

# Test Build Tools
Write-Host "`n[5/7] Testing Build Tools..." -ForegroundColor Yellow
$tools = @{
    "Ninja" = "ninja"
    "CMake" = "cmake"
    "Git" = "git"
}
foreach ($tool in $tools.GetEnumerator()) {
    if (Get-Command $tool.Value -ErrorAction SilentlyContinue) {
        $version = & $tool.Value --version 2>&1 | Select-Object -First 1
        Write-Host "  OK - $($tool.Key): $version" -ForegroundColor Green
    } else {
        Write-Host "  FAIL - $($tool.Key) not found" -ForegroundColor Red
        $failCount++
    }
}

# Test Visual Studio Build Tools
Write-Host "`n[6/7] Testing Visual Studio Build Tools..." -ForegroundColor Yellow
if (Test-Path "C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools\VC\Auxiliary\Build\vcvars64.bat") {
    Write-Host "  OK - VS Build Tools found" -ForegroundColor Green
} else {
    Write-Host "  FAIL - VS Build Tools not found" -ForegroundColor Red
    $failCount++
}

# Test Environment Variables
Write-Host "`n[7/7] Testing Environment Variables..." -ForegroundColor Yellow
$envVars = @{
    "CUDA_PATH" = "C:\Program Files\NVIDIA GPU Computing Toolkit\CUDA\v12.8"
    "CUDA_HOME" = "C:\Program Files\NVIDIA GPU Computing Toolkit\CUDA\v12.8"
}
foreach ($var in $envVars.GetEnumerator()) {
    $actualValue = [Environment]::GetEnvironmentVariable($var.Key)
    if ($actualValue -eq $var.Value) {
        Write-Host "  OK - $($var.Key) = $($var.Value)" -ForegroundColor Green
    } else {
        Write-Host "  WARN - $($var.Key) = $actualValue (expected: $($var.Value))" -ForegroundColor Yellow
    }
}

# Summary
Write-Host "`n========================================" -ForegroundColor Cyan
if ($failCount -eq 0) {
    Write-Host "ALL TESTS PASSED - Ready to build!" -ForegroundColor Green
} else {
    Write-Host "FAILED: $failCount test(s) failed" -ForegroundColor Red
}
Write-Host "========================================" -ForegroundColor Cyan
