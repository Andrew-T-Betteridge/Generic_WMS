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
$tests = @(
    "database\tests\004_warehouse_execution_lifecycle.sql",
    "database\tests\005_warehouse_execution_edge_cases.sql"
)
foreach ($test in $tests) {
    Write-Host "Running: $test"
    & $Psql -U $DbUser -d $Database -v ON_ERROR_STOP=1 -f $test
    if ($LASTEXITCODE -ne 0) { throw "Warehouse execution test failed: $test" }
}
Write-Host "Warehouse Execution V1 tests passed."
