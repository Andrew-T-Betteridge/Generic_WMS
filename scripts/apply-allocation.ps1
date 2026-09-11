param(
    [string]$Database = "fulfilment_dev",
    [string]$DbUser = "postgres"
)

$ErrorActionPreference = "Stop"
$Psql = "C:\Program Files\PostgreSQL\18\bin\psql.exe"

function Invoke-PsqlFile {
    param([string]$File)

    Write-Host "Applying: $File"

    & $Psql `
        -U $DbUser `
        -d $Database `
        -v ON_ERROR_STOP=1 `
        -f $File

    if ($LASTEXITCODE -ne 0) {
        throw "Failed applying $File"
    }
}

# Migration makes this safe for an existing database.
Invoke-PsqlFile "database\migrations\0007_add_allocation.sql"

# Ensure the canonical table definition is present in the repository build path.
Invoke-PsqlFile "database\tables\core\ALLOCATION.sql"

Invoke-PsqlFile "database\indexes\003_allocation_indexes.sql"
Invoke-PsqlFile "database\views\core\INVENTORY_AVAILABILITY.sql"
Invoke-PsqlFile "database\functions\core\ALLOCATE_ORDER.sql"
Invoke-PsqlFile "database\functions\core\DEALLOCATE_ORDER.sql"

Write-Host ""
Write-Host "Generic WMS allocation build completed successfully."
