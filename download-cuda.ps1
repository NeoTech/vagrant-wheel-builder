# download-cuda.ps1
# Downloads CUDA installer directly from NVIDIA
# Place this script next to the Vagrantfile and run before 'vagrant up'

param(
    [switch]$List,     # List available CUDA versions
    [string]$Version   # Override version from config (e.g., "12.8")
)

$ErrorActionPreference = "Stop"

# Known CUDA versions and their download URLs
# Format: cuda_<version>_<driver>_windows.exe
#
# To add a new version:
#   1. Visit https://developer.nvidia.com/cuda-toolkit-archive
#   2. Find the Windows local installer (.exe) download link
#   3. Add entry below with major.minor as key (e.g., "12.9")
#   4. URL pattern: https://developer.download.nvidia.com/compute/cuda/<VER>/local_installers/cuda_<VER>_<DRIVER>_windows.exe
#
$script:KnownVersions = [ordered]@{
    "12.8" = @{
        "version" = "12.8.0"
        "driver" = "571.96"
        "url" = "https://developer.download.nvidia.com/compute/cuda/12.8.0/local_installers/cuda_12.8.0_571.96_windows.exe"
    }
    "12.6" = @{
        "version" = "12.6.0"
        "driver" = "560.76"
        "url" = "https://developer.download.nvidia.com/compute/cuda/12.6.0/local_installers/cuda_12.6.0_560.76_windows.exe"
    }
    "12.5" = @{
        "version" = "12.5.0"
        "driver" = "555.85"
        "url" = "https://developer.download.nvidia.com/compute/cuda/12.5.0/local_installers/cuda_12.5.0_555.85_windows.exe"
    }
    "12.4" = @{
        "version" = "12.4.0"
        "driver" = "551.61"
        "url" = "https://developer.download.nvidia.com/compute/cuda/12.4.0/local_installers/cuda_12.4.0_551.61_windows.exe"
    }
    "12.3" = @{
        "version" = "12.3.0"
        "driver" = "545.84"
        "url" = "https://developer.download.nvidia.com/compute/cuda/12.3.0/local_installers/cuda_12.3.0_545.84_windows.exe"
    }
    "12.2" = @{
        "version" = "12.2.0"
        "driver" = "535.54"
        "url" = "https://developer.download.nvidia.com/compute/cuda/12.2.0/local_installers/cuda_12.2.0_535.54_windows.exe"
    }
    "12.1" = @{
        "version" = "12.1.0"
        "driver" = "531.14"
        "url" = "https://developer.download.nvidia.com/compute/cuda/12.1.0/local_installers/cuda_12.1.0_531.14_windows.exe"
    }
    "12.0" = @{
        "version" = "12.0.0"
        "driver" = "527.41"
        "url" = "https://developer.download.nvidia.com/compute/cuda/12.0.0/local_installers/cuda_12.0.0_527.41_windows.exe"
    }
    "11.8" = @{
        "version" = "11.8.0"
        "driver" = "522.06"
        "url" = "https://developer.download.nvidia.com/compute/cuda/11.8.0/local_installers/cuda_11.8.0_522.06_windows.exe"
    }
}

# Get script directory (where Vagrantfile should be)
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$configPath = Join-Path $scriptDir "output\build-config.toml"

# Helper function to read values from build-config.toml
function Get-ConfigValue {
    param(
        [Parameter(Mandatory=$true)]
        [string]$Key,
        [string]$ConfigPath
    )
    
    if (-not (Test-Path $ConfigPath)) {
        return $null
    }
    
    $content = Get-Content $ConfigPath -Raw
    if ($content -match "(?m)^\s*$Key\s*=\s*[`"']([^`"']+)[`"']") {
        return $matches[1]
    }
    return $null
}

# List available versions
if ($List) {
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host "Available CUDA Versions" -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "Version  Full Version   Driver    Size (approx)" -ForegroundColor White
    Write-Host "-------  ------------   ------    -------------" -ForegroundColor Gray
    
    foreach ($key in $script:KnownVersions.Keys) {
        $info = $script:KnownVersions[$key]
        Write-Host ("{0,-8} {1,-14} {2,-9} ~3 GB" -f $key, $info.version, $info.driver) -ForegroundColor Green
    }
    
    Write-Host ""
    Write-Host "Usage:" -ForegroundColor Yellow
    Write-Host "  .\download-cuda.ps1              # Download version from build-config.toml" -ForegroundColor Gray
    Write-Host "  .\download-cuda.ps1 -Version 12.6 # Download specific version" -ForegroundColor Gray
    exit 0
}

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "CUDA Installer Downloader" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

# Determine target version
$cudaVersion = $Version
if (-not $cudaVersion) {
    $cudaVersion = Get-ConfigValue -Key "cuda_version" -ConfigPath $configPath
    if (-not $cudaVersion) {
        Write-Host "WARNING: Could not read cuda_version from $configPath, defaulting to 12.8" -ForegroundColor Yellow
        $cudaVersion = "12.8"
    }
}

Write-Host "Target CUDA version: $cudaVersion" -ForegroundColor Green


# Validate version
if (-not ($script:KnownVersions.Keys -contains $cudaVersion)) {
    Write-Host "ERROR: Unknown CUDA version '$cudaVersion'" -ForegroundColor Red
    Write-Host ""
    Write-Host "Run with -List to see available versions:" -ForegroundColor Yellow
    Write-Host "  .\download-cuda.ps1 -List" -ForegroundColor Gray
    exit 1
}

$versionInfo = $script:KnownVersions[$cudaVersion]
$fileName = "cuda_$($versionInfo.version)_$($versionInfo.driver)_windows.exe"
$outputPath = Join-Path $scriptDir $fileName

# Check if already downloaded
if (Test-Path $outputPath) {
    Write-Host "CUDA installer already exists: $fileName" -ForegroundColor Green
    Write-Host "Delete the file to re-download." -ForegroundColor Gray
    exit 0
}

Write-Host ""
Write-Host "Downloading $fileName..." -ForegroundColor Yellow
Write-Host "URL: $($versionInfo.url)" -ForegroundColor Gray
Write-Host "This may take a while (~3GB)..." -ForegroundColor Gray
Write-Host ""

try {
    # Use BITS for better download experience on Windows (supports resume, progress)
    $bitsSupported = Get-Command Start-BitsTransfer -ErrorAction SilentlyContinue
    if ($bitsSupported) {
        Start-BitsTransfer -Source $versionInfo.url -Destination $outputPath -DisplayName "Downloading CUDA $cudaVersion" -Description $fileName
    } else {
        # Fallback to Invoke-WebRequest with progress
        $ProgressPreference = 'Continue'
        Invoke-WebRequest -Uri $versionInfo.url -OutFile $outputPath -UseBasicParsing
    }
    
    # Verify download
    if (Test-Path $outputPath) {
        $fileSize = (Get-Item $outputPath).Length / 1GB
        Write-Host ""
        Write-Host "Download complete!" -ForegroundColor Green
        Write-Host "  File: $fileName" -ForegroundColor Cyan
        Write-Host "  Size: $([math]::Round($fileSize, 2)) GB" -ForegroundColor Cyan
    } else {
        throw "Download completed but file not found"
    }
} catch {
    Write-Host "ERROR: Failed to download CUDA installer" -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red
    
    # Cleanup partial download
    if (Test-Path $outputPath) {
        Remove-Item $outputPath -Force -ErrorAction SilentlyContinue
    }
    exit 1
}

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "CUDA installer ready!" -ForegroundColor Green
Write-Host "You can now run 'vagrant up' to provision the VM" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
