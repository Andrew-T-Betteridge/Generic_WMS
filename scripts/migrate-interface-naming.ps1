param(
    [string]$Database = "fulfilment_dev",
    [string]$DbUser = "postgres"
)

$ErrorActionPreference = "Stop"
$Psql = "C:\Program Files\PostgreSQL\18\bin\psql.exe"

& $Psql -U $DbUser -d $Database -v ON_ERROR_STOP=1 -f "database\migrations\0004_rename_iface_to_interface.sql"
if ($LASTEXITCODE -ne 0) { throw "Interface schema migration failed." }

Write-Host "Database schema naming migrated to interface."
Write-Host ""
Write-Host "Repository cleanup:"
Write-Host "  Delete database\schemas\002_iface.sql if it still exists."
Write-Host "  Delete database\tables\iface if it still exists."
