param(
    [string]$Database = "fulfilment_dev",
    [string]$DbUser = "postgres"
)
$ErrorActionPreference = "Stop"
$Psql = "C:\Program Files\PostgreSQL\18\bin\psql.exe"

$Tests = @(
    "database\tests\010_merge_consolidation_smoke_test.sql",
    "database\tests\011_merge_consolidation_edge_cases.sql"
)

foreach ($Test in $Tests) {
    Write-Host "Running: $Test"
    & $Psql -U $DbUser -d $Database -v ON_ERROR_STOP=1 -f $Test
    if ($LASTEXITCODE -ne 0) {
        throw "Merge / Consolidation test failed: $Test"
    }
}

Write-Host ""
Write-Host "Merge / Consolidation V1 tests passed."
