param(
    [string]$Database = "fulfilment_dev",
    [string]$DbUser = "postgres"
)

$ErrorActionPreference = "Stop"
$Psql = "C:\Program Files\PostgreSQL\18\bin\psql.exe"

if (-not (Test-Path $Psql)) {
    throw "PostgreSQL psql.exe not found at: $Psql"
}

$files = @(
    "database\tables\core\SKU.sql",
    "database\tables\core\LOCATION.sql",
    "database\tables\core\ADDRESS.sql",
    "database\tables\core\INVENTORY.sql",
    "database\tables\core\ORDER_HEADER.sql",
    "database\tables\core\ORDER_LINE.sql",
    "database\tables\core\INVENTORY_TRANSACTION.sql",
    "database\tables\core\SHIPPING_MANIFEST.sql"
)

Write-Host ""
Write-Host "Building Generic WMS core tables..."
Write-Host "Database: $Database"
Write-Host ""

foreach ($file in $files) {
    if (-not (Test-Path $file)) {
        throw "SQL file not found: $file"
    }

    Write-Host "Applying: $file"

    & $Psql `
        -U $DbUser `
        -d $Database `
        -v ON_ERROR_STOP=1 `
        -f $file

    if ($LASTEXITCODE -ne 0) {
        throw "Core database build failed while applying: $file"
    }
}

Write-Host ""
Write-Host "Generic WMS core table build completed successfully."
