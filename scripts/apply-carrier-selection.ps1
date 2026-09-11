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

    if ($LASTEXITCODE -ne 0) {
        throw "Failed applying $File"
    }
}

Invoke-SqlFile "database\migrations\0009_carrier_selection_v1.sql"
Invoke-SqlFile "database\tables\config\CARRIER_SERVICE_RATE.sql"
Invoke-SqlFile "database\indexes\005_carrier_selection_indexes.sql"
Invoke-SqlFile "database\functions\config\CARRIER_CONDITION_MATCH.sql"
Invoke-SqlFile "database\functions\core\SELECT_CARRIER.sql"
Invoke-SqlFile "database\functions\core\OVERRIDE_CARRIER.sql"
Invoke-SqlFile "database\views\core\CARRIER_SELECTION_WORKBENCH.sql"
Invoke-SqlFile "database\views\core\CARRIER_DECISION_EXPLANATION.sql"

Write-Host ""
Write-Host "Carrier Selection V1 applied successfully."
