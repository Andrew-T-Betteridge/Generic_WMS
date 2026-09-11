param(
    [string]$Database = "fulfilment_dev",
    [string]$DbUser = "postgres"
)
$ErrorActionPreference = "Stop"
$Psql = "C:\Program Files\PostgreSQL\18\bin\psql.exe"

& $Psql -U $DbUser -d $Database -v ON_ERROR_STOP=1 -f "database\migrations\0006_remove_interface_error.sql"
if ($LASTEXITCODE -ne 0) { throw "Could not remove INTERFACE_ERROR." }

Remove-Item "database\tables\interface\INTERFACE_ERROR.sql" -ErrorAction SilentlyContinue
Remove-Item "database\tables\iface\INTERFACE_ERROR.sql" -ErrorAction SilentlyContinue

Write-Host "INTERFACE_ERROR removed."
