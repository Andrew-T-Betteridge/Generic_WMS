param()

$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot

Write-Host ""
Write-Host "===================================================="
Write-Host "DYNETIC WMS 0.2.0 PRODUCTION READINESS"
Write-Host "===================================================="

& "$PSScriptRoot\test-prod-smoke.ps1"
if ($LASTEXITCODE -ne 0) { throw "Production database smoke check failed." }

$prodEnv = Join-Path $repoRoot "config\environments\production.api.env"
if (Test-Path $prodEnv) {
    & "$PSScriptRoot\validate-prod-api-config.ps1" -EnvironmentFile $prodEnv
    if ($LASTEXITCODE -ne 0) { throw "Production API config validation failed." }
} else {
    Write-Host ""
    Write-Host "[INFO] Production API secrets/config have not been created yet."
    Write-Host "       This is expected until OIDC and live-payment activation are ready."
}

Write-Host ""
Write-Host "===================================================="
Write-Host "DATABASE PRODUCTION BASELINE IS READY"
Write-Host "===================================================="
Write-Host "Database .............. fulfilment_prod"
Write-Host "Version ............... 0.2.0"
Write-Host "Traffic ............... NOT ENABLED BY THIS SCRIPT"
Write-Host "Live Stripe ........... NOT ENABLED BY THIS SCRIPT"
Write-Host "===================================================="
