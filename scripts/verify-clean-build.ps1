param([string]$TestDatabase="fulfilment_build_test",[string]$DbUser="postgres",[switch]$KeepDatabase)
$ErrorActionPreference="Stop"
$Psql="C:\Program Files\PostgreSQL\18\bin\psql.exe"
$Drop='DROP DATABASE IF EXISTS "{0}" WITH (FORCE);' -f $TestDatabase
$Create='CREATE DATABASE "{0}";' -f $TestDatabase

Write-Host "DYNETIC WMS clean verification"
& $Psql -U $DbUser -d postgres -v ON_ERROR_STOP=1 -c $Drop
if($LASTEXITCODE -ne 0){throw "Could not drop old test database."}
& $Psql -U $DbUser -d postgres -v ON_ERROR_STOP=1 -c $Create
if($LASTEXITCODE -ne 0){throw "Could not create clean test database."}

try {
    & "$PSScriptRoot\build-database.ps1" -Database $TestDatabase -DbUser $DbUser
    if($LASTEXITCODE -ne 0){throw "Clean build failed."}

    $Tests=@(
      "test-order-interface.ps1",
      "test-order-allocation.ps1",
      "test-warehouse-execution.ps1",
      "test-carrier-selection.ps1",
      "test-fulfilment-holds.ps1",
      "test-merge-consolidation.ps1",
      "test-website-catalogue.ps1",
      "test-website-checkout-order-api.ps1",
      "test-website-domain-v2.ps1",
      "test-system-version.ps1",
      "test-website-api-v3.ps1"
    )
    foreach($Test in $Tests){
      & (Join-Path $PSScriptRoot $Test) -Database $TestDatabase -DbUser $DbUser
      if($LASTEXITCODE -ne 0){throw "Test failed: $Test"}
    }

    Write-Host ""
    Write-Host "DYNETIC WMS CLEAN BUILD + WEBSITE/API V3 + PAYMENT/ACCOUNT/SECURITY TESTS PASSED."
}
finally {
    if(-not $KeepDatabase){
      Write-Host "Removing temporary test database: $TestDatabase"
      & $Psql -U $DbUser -d postgres -v ON_ERROR_STOP=1 -c $Drop
    }
}
