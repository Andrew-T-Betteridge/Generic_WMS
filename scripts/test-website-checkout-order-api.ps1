param(
    [string]$Database = "fulfilment_dev",
    [string]$DbUser = "postgres"
)
$ErrorActionPreference = "Stop"
$Psql = "C:\Program Files\PostgreSQL\18\bin\psql.exe"

$Test = "database\tests\013_website_checkout_order_api_test.sql"
Write-Host "Running: $Test"
& $Psql -U $DbUser -d $Database -v ON_ERROR_STOP=1 -P pager=off -f $Test
if ($LASTEXITCODE -ne 0) {
    throw "Website Checkout & Order API test failed: $Test"
}
Write-Host ""
Write-Host "Website Checkout & Order API V1 tests passed."
