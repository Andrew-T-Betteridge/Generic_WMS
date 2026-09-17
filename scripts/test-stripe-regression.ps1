param(
    [string]$BaseUrl = "http://localhost:3001",
    [string]$DatabaseName = "fulfilment_test"
)
# DYNETIC_TEST_WRAPPER_GUARD_BEGIN
. "$PSScriptRoot\Test-Safety.ps1"
$null = Assert-DyneticTestScriptSafety -ScriptPath $MyInvocation.MyCommand.Path -BoundParameters $PSBoundParameters
# DYNETIC_TEST_WRAPPER_GUARD_END


$ErrorActionPreference = "Stop"

. "$PSScriptRoot\Test-Safety.ps1"
$null = Assert-DyneticNonProductionApi -BaseUrl $BaseUrl
Write-Host ""
Write-Host "===================================================="
Write-Host "DYNETIC WMS EXTERNAL STRIPE REGRESSION"
Write-Host "===================================================="

& "$PSScriptRoot\test-stripe-e2e.ps1" -BaseUrl $BaseUrl -DatabaseName $DatabaseName
if ($LASTEXITCODE -ne 0) { throw "Stripe success E2E failed." }

& "$PSScriptRoot\test-stripe-lifecycle.ps1" -BaseUrl $BaseUrl -DatabaseName $DatabaseName
if ($LASTEXITCODE -ne 0) { throw "Stripe lifecycle regression failed." }

Write-Host ""
Write-Host "===================================================="
Write-Host "DYNETIC WMS EXTERNAL STRIPE REGRESSION PASSED"
Write-Host "===================================================="
