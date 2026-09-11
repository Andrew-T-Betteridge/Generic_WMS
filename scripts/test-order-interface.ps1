param(
    [string]$Database = "fulfilment_dev",
    [string]$DbUser = "postgres"
)

$ErrorActionPreference = "Stop"
$Psql = "C:\Program Files\PostgreSQL\18\bin\psql.exe"

& $Psql -U $DbUser -d $Database -v ON_ERROR_STOP=1 -f "database\tests\001_order_interface_smoke_test.sql"
if ($LASTEXITCODE -ne 0) { throw "Order interface smoke test failed." }
