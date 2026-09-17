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

$Tests = @(
    "database\tests\008_fulfilment_holds_smoke_test.sql",
    "database\tests\009_fulfilment_preference_edge_cases.sql"
)
foreach ($Test in $Tests) {
    Write-Host "Running: $Test"
    & $Psql -U $DbUser -d $Database -v ON_ERROR_STOP=1 -f $Test
    if ($LASTEXITCODE -ne 0) { throw "Fulfilment Hold test failed: $Test" }
}
Write-Host ""
Write-Host "Fulfilment Holds V1 tests passed."
