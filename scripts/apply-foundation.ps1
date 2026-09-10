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
    "database\schemas\001_core.sql",
    "database\schemas\002_iface.sql",
    "database\schemas\003_config.sql",
    "database\schemas\004_audit.sql",

    "database\tables\core\CLIENT.sql",

    "database\tables\config\CARRIER.sql",
    "database\tables\config\CARRIER_SERVICE.sql",
    "database\tables\config\CARRIER_SELECTION_RULE.sql",
    "database\tables\config\MERGE_RULE.sql",

    "database\tables\iface\INTERFACE_ERROR.sql",
    "database\tables\audit\PROCESSING_LOG.sql",

    "database\indexes\001_config_indexes.sql",
    "database\seed\001_client.sql"
)

Write-Host ""
Write-Host "Building Generic WMS foundation..."
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
        throw "Database build failed while applying: $file"
    }
}

Write-Host ""
Write-Host "Generic WMS foundation build completed successfully."