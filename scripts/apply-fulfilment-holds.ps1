param(
    [string]$Database = "fulfilment_dev",
    [string]$DbUser = "postgres"
)
$ErrorActionPreference = "Stop"
$Psql = "C:\Program Files\PostgreSQL\18\bin\psql.exe"

function Invoke-SqlFile {
    param([string]$File)
    Write-Host "Applying: $File"
    & $Psql -U $DbUser -d $Database -v ON_ERROR_STOP=1 -f $File
    if ($LASTEXITCODE -ne 0) { throw "Failed applying $File" }
}

Invoke-SqlFile "database\migrations\0010_fulfilment_holds_v1.sql"
Invoke-SqlFile "database\indexes\006_fulfilment_hold_indexes.sql"
Invoke-SqlFile "database\functions\core\EVALUATE_DELIVERY_HOLD.sql"
Invoke-SqlFile "database\functions\core\SET_DELIVERY_HOLD.sql"
Invoke-SqlFile "database\functions\core\RELEASE_DELIVERY_HOLD.sql"
Invoke-SqlFile "database\functions\core\SET_FULFILMENT_PREFERENCE.sql"
Invoke-SqlFile "database\functions\core\SET_CONTAINER_FULFILMENT.sql"
Invoke-SqlFile "database\views\core\MIXED_ORDER_FULFILMENT_WORKBENCH.sql"
Invoke-SqlFile "database\views\core\DELIVERY_HOLD_WORKBENCH.sql"

Write-Host ""
Write-Host "Fulfilment Holds V1 applied successfully."
