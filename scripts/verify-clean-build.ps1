param(
    [string]$TestDatabase = "fulfilment_build_test",
    [string]$DbUser = "postgres",
    [switch]$KeepDatabase
)

$ErrorActionPreference = "Stop"
$Psql = "C:\Program Files\PostgreSQL\18\bin\psql.exe"

if (-not (Test-Path $Psql)) {
    throw "psql.exe was not found at: $Psql"
}

# Build SQL in variables so PowerShell passes the whole -c value to psql
# as one argument. This avoids nested quote parsing problems.
$DropDatabaseSql = 'DROP DATABASE IF EXISTS "{0}" WITH (FORCE);' -f $TestDatabase
$CreateDatabaseSql = 'CREATE DATABASE "{0}";' -f $TestDatabase

Write-Host "Dropping old test database if present: $TestDatabase"
& $Psql -U $DbUser -d postgres -v ON_ERROR_STOP=1 -c $DropDatabaseSql
if ($LASTEXITCODE -ne 0) {
    throw "Could not drop old test database."
}

Write-Host "Creating clean test database: $TestDatabase"
& $Psql -U $DbUser -d postgres -v ON_ERROR_STOP=1 -c $CreateDatabaseSql
if ($LASTEXITCODE -ne 0) {
    throw "Could not create test database."
}

try {
    Write-Host ""
    Write-Host "Building Generic WMS in clean database..."
    & "$PSScriptRoot\build-database.ps1" -Database $TestDatabase -DbUser $DbUser
    if ($LASTEXITCODE -ne 0) {
        throw "Clean build failed."
    }

    Write-Host ""
    Write-Host "Running order interface smoke test..."
    & "$PSScriptRoot\test-order-interface.ps1" -Database $TestDatabase -DbUser $DbUser
    if ($LASTEXITCODE -ne 0) {
        throw "Order interface smoke test failed."
    }

    Write-Host ""
    Write-Host "Running allocation tests..."
    & "$PSScriptRoot\test-order-allocation.ps1" -Database $TestDatabase -DbUser $DbUser
    if ($LASTEXITCODE -ne 0) {
        throw "Allocation tests failed."
    }

    Write-Host ""
    Write-Host "Running warehouse execution tests..."
    & "$PSScriptRoot\test-warehouse-execution.ps1" -Database $TestDatabase -DbUser $DbUser
    if ($LASTEXITCODE -ne 0) {
        throw "Warehouse execution tests failed."
    }

    Write-Host ""
    Write-Host "CLEAN BUILD + INTERFACE + ALLOCATION + WAREHOUSE EXECUTION TESTS PASSED."
}
finally {
    if (-not $KeepDatabase) {
        $DropDatabaseSql = 'DROP DATABASE IF EXISTS "{0}" WITH (FORCE);' -f $TestDatabase

        Write-Host ""
        Write-Host "Removing temporary test database: $TestDatabase"
        & $Psql -U $DbUser -d postgres -v ON_ERROR_STOP=1 -c $DropDatabaseSql

        if ($LASTEXITCODE -ne 0) {
            Write-Warning "Could not remove temporary test database: $TestDatabase"
        } else {
            Write-Host "Temporary test database removed."
        }
    }
    else {
        Write-Host "Temporary test database kept: $TestDatabase"
    }
}
