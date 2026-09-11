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

Invoke-SqlFile "database\migrations\0011_merge_consolidation_v1.sql"
Invoke-SqlFile "database\tables\config\MERGE_RULE.sql"
Invoke-SqlFile "database\tables\config\MERGE_RULE_CONDITION.sql"
Invoke-SqlFile "database\indexes\007_merge_consolidation_indexes.sql"
Invoke-SqlFile "database\functions\config\MERGE_CONDITION_MATCH.sql"
Invoke-SqlFile "database\functions\core\EVALUATE_CONTAINER_MERGE.sql"
Invoke-SqlFile "database\functions\core\MERGE_CONTAINERS.sql"
Invoke-SqlFile "database\views\core\CONTAINER_MERGE_CANDIDATE_WORKBENCH.sql"
Invoke-SqlFile "database\views\core\MERGE_DECISION_EXPLANATION.sql"

Write-Host ""
Write-Host "Merge / Consolidation V1 applied successfully."
