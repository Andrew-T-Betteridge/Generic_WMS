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

& $Psql -U $DbUser -d $Database -v ON_ERROR_STOP=1 -f "database\tests\001_order_interface_smoke_test.sql"
if ($LASTEXITCODE -ne 0) { throw "Order interface smoke test failed." }
