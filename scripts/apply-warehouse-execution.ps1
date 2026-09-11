param(
    [string]$Database = "fulfilment_dev",
    [string]$DbUser = "postgres"
)
$ErrorActionPreference = "Stop"
$Psql = "C:\Program Files\PostgreSQL\18\bin\psql.exe"

$files = @(
    "database\migrations\0008_warehouse_execution_v1.sql",
    "database\tables\core\PICK_TASK.sql",
    "database\indexes\004_warehouse_execution_indexes.sql",
    "database\views\core\PICK_WORK_QUEUE.sql",
    "database\views\core\ORDER_FULFILMENT_WORKBENCH.sql",
    "database\views\core\INVENTORY_RESERVATION_RECONCILIATION.sql",
    "database\views\core\SHIPMENT_WORK_QUEUE.sql",
    "database\functions\core\ALLOCATE_ORDER.sql",
    "database\functions\core\DEALLOCATE_ORDER.sql",
    "database\functions\core\CREATE_PICK_TASKS.sql",
    "database\functions\core\CONFIRM_PICK.sql",
    "database\functions\core\PACK_ORDER.sql",
    "database\functions\core\SHIP_CONTAINER.sql"
)
foreach ($file in $files) {
    Write-Host "Applying: $file"
    & $Psql -U $DbUser -d $Database -v ON_ERROR_STOP=1 -f $file
    if ($LASTEXITCODE -ne 0) { throw "Warehouse execution build failed while applying: $file" }
}
Write-Host "Warehouse Execution V1 applied successfully."
