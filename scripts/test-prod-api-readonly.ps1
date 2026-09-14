param(
    [string]$BaseUrl = "http://localhost:3001"
)

$ErrorActionPreference = "Stop"

Write-Host ""
Write-Host "===================================================="
Write-Host "DYNETIC WMS PRODUCTION API READ-ONLY SMOKE CHECK"
Write-Host "===================================================="
Write-Host "API ................... $BaseUrl"
Write-Host "Write calls ........... NONE"
Write-Host "===================================================="

$health = Invoke-RestMethod -Uri "$BaseUrl/health" -Method Get
if (-not $health.ok) {
    throw "API health endpoint is not healthy."
}
Write-Host "[PASS] /health"

$version = Invoke-RestMethod -Uri "$BaseUrl/api/system/version" -Method Get
$versionValue = if ($version.version) { [string]$version.version } elseif ($version.current.version) { [string]$version.current.version } else { "" }
if ($versionValue -ne "0.2.0") {
    throw "Expected DYNETIC WMS 0.2.0 but API returned '$versionValue'."
}
Write-Host "[PASS] /api/system/version = 0.2.0"

$catalog = Invoke-RestMethod -Uri "$BaseUrl/api/catalog/products" -Method Get
$items = @()
if ($catalog -is [System.Array]) {
    $items = @($catalog)
} elseif ($catalog.products) {
    $items = @($catalog.products)
} elseif ($catalog.items) {
    $items = @($catalog.items)
}

if ($items.Count -lt 1) {
    throw "Production catalogue endpoint returned no products."
}
Write-Host "[PASS] /api/catalog/products returned $($items.Count) product(s)"

$product = Invoke-RestMethod `
    -Uri "$BaseUrl/api/catalog/products/finatics-aquatics-air-driven-fry-tray" `
    -Method Get

if (-not $product) {
    throw "Seed product endpoint returned no product."
}
Write-Host "[PASS] Fry tray product endpoint"

Write-Host ""
Write-Host "===================================================="
Write-Host "PRODUCTION API READ-ONLY SMOKE CHECK PASSED"
Write-Host "===================================================="
