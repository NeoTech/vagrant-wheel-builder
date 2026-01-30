# build-all.ps1
# Build all CUDA wheels sequentially

$ErrorActionPreference = "Continue"

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "CUDA Wheel Builder - Build All" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

$scripts = @(
    "C:\output\build-flash-attention.ps1",
    "C:\output\build-sageattention.ps1",
    "C:\output\build-nunchaku.ps1",
    "C:\output\build-triton.ps1"
)

$results = @{}

foreach ($script in $scripts) {
    $name = [System.IO.Path]::GetFileNameWithoutExtension($script) -replace "build-", ""
    
    Write-Host "`n========================================" -ForegroundColor Magenta
    Write-Host "Starting: $name" -ForegroundColor Magenta
    Write-Host "========================================" -ForegroundColor Magenta
    
    & powershell.exe -ExecutionPolicy Bypass -File $script
    
    if ($LASTEXITCODE -eq 0) {
        $results[$name] = "SUCCESS"
    } else {
        $results[$name] = "FAILED"
    }
}

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "Build Summary" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

foreach ($result in $results.GetEnumerator()) {
    $color = if ($result.Value -eq "SUCCESS") { "Green" } else { "Red" }
    Write-Host "  $($result.Key): $($result.Value)" -ForegroundColor $color
}

Write-Host "`nBuilt wheels:" -ForegroundColor Green
$wheels = Get-ChildItem "C:\output\wheels\*.whl" -ErrorAction SilentlyContinue
if ($wheels) {
    foreach ($wheel in $wheels) {
        $sizeMB = [math]::Round($wheel.Length / 1MB, 2)
        Write-Host "  - $($wheel.Name) ($sizeMB MB)" -ForegroundColor White
    }
} else {
    Write-Host "  No wheels found" -ForegroundColor Yellow
}
