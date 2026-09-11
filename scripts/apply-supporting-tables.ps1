param(
    [string]$Database = "fulfilment_dev",
    [string]$DbUser = "postgres"
)

$ErrorActionPreference = "Stop"
$Psql = "C:\Program Files\PostgreSQL\18\bin\psql.exe"

$files = @(
    "database\tables\core\SITE.sql",
    "database\tables\core\PRODUCT_GROUP.sql",
    "database\tables\core\SKU_MEDIA.sql",
    "database\tables\core\SUPPLIER.sql",
    "database\tables\core\SUPPLIER_SKU.sql",
    "database\tables\core\LOCATION_ZONE.sql",
    "database\tables\core\ORDER_CONTAINER.sql",
    "database\tables\core\PRE_ADVICE_HEADER.sql",
    "database\tables\core\PRE_ADVICE_LINE.sql",
    "database\tables\core\KIT_HEADER.sql",
    "database\tables\core\KIT_LINE.sql",
    "database\tables\interface\ORDER_HEADER_IF.sql",
    "database\tables\interface\ORDER_LINE_IF.sql",
    "database\tables\interface\PRE_ADVICE_HEADER_IF.sql",
    "database\tables\interface\PRE_ADVICE_LINE_IF.sql",
    "database\tables\interface\INVENTORY_ADJUST_IF.sql",
    "database\tables\config\CARRIER_SELECTION_CONDITION.sql",
    "database\tables\config\MERGE_RULE_CONDITION.sql",
    "database\tables\config\ALLOCATION_RULE.sql",
    "database\tables\config\ALLOCATION_RULE_CONDITION.sql",
    "database\tables\config\SYSTEM_SETTING.sql",
    "database\tables\config\FEATURE_FLAG.sql",
    "database\tables\audit\AUDIT_EVENT.sql",
    "database\tables\audit\RULE_DECISION_LOG.sql",
    "database\indexes\002_supporting_indexes.sql",
    "database\functions\interface\PROCESS_ORDER_INTERFACE.sql"
)

foreach ($file in $files) {
    Write-Host "Applying: $file"
    & $Psql -U $DbUser -d $Database -v ON_ERROR_STOP=1 -f $file
    if ($LASTEXITCODE -ne 0) { throw "Supporting build failed while applying: $file" }
}

Write-Host "Generic WMS supporting build completed successfully."
