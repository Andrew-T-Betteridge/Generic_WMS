param(
    [string]$Database = "fulfilment_dev",
    [string]$DbUser = "postgres"
)
# DYNETIC_TEST_WRAPPER_GUARD_BEGIN
. "$PSScriptRoot\Test-Safety.ps1"
$null = Assert-DyneticTestScriptSafety -ScriptPath $MyInvocation.MyCommand.Path -BoundParameters $PSBoundParameters
# DYNETIC_TEST_WRAPPER_GUARD_END


$ErrorActionPreference = "Stop"
$Psql = "C:\Program Files\PostgreSQL\18\bin\psql.exe"

& $Psql `
    -U $DbUser `
    -d $Database `
    -v ON_ERROR_STOP=1 `
    -f "database\tests\002_order_allocation_smoke_test.sql"

if ($LASTEXITCODE -ne 0) {
    throw "Order allocation smoke test failed."
}

& $Psql `
    -U $DbUser `
    -d $Database `
    -v ON_ERROR_STOP=1 `
    -f "database\tests\003_allocation_edge_cases.sql"

if ($LASTEXITCODE -ne 0) {
    throw "Allocation edge-case tests failed."
}

Write-Host ""
Write-Host "Order allocation tests completed successfully."
