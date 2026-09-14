param(
    [string]$DatabaseName = "fulfilment_prod"
)

$ErrorActionPreference = "Stop"

function Read-DotEnv([string]$Path) {
    $values = @{}
    if (-not (Test-Path $Path)) { return $values }

    foreach ($line in Get-Content $Path) {
        $trimmed = $line.Trim()
        if (-not $trimmed -or $trimmed.StartsWith("#")) { continue }
        $eq = $trimmed.IndexOf("=")
        if ($eq -lt 1) { continue }
        $values[$trimmed.Substring(0,$eq).Trim()] = $trimmed.Substring($eq+1).Trim()
    }
    return $values
}

function Invoke-PsqlScalar([string]$Sql) {
    $psql = "C:\Program Files\PostgreSQL\18\bin\psql.exe"
    if (-not (Test-Path $psql)) { throw "psql not found at $psql" }

    $result = & $psql -X -t -A -P pager=off -v ON_ERROR_STOP=1 `
        -h $dbHost -p $dbPort -U $dbUser -d $DatabaseName -c $Sql

    if ($LASTEXITCODE -ne 0) { throw "psql scalar command failed." }
    return (($result | Out-String).Trim())
}

function Assert-Equal([string]$Label,[string]$Actual,[string]$Expected) {
    if ($Actual -ne $Expected) {
        throw "$Label failed. Expected '$Expected' but got '$Actual'."
    }
    Write-Host "[PASS] $Label"
}

function Assert-Positive([string]$Label,[string]$Actual) {
    [decimal]$value = 0
    if (-not [decimal]::TryParse($Actual,[ref]$value) -or $value -le 0) {
        throw "$Label failed. Expected a positive value but got '$Actual'."
    }
    Write-Host "[PASS] $Label ($Actual)"
}

$repoRoot = Split-Path -Parent $PSScriptRoot
$apiEnvPath = Join-Path $repoRoot "apps\api\.env"
$envValues = Read-DotEnv $apiEnvPath

$dbHost = if ($envValues["DB_HOST"]) { $envValues["DB_HOST"] } else { "localhost" }
$dbPort = if ($envValues["DB_PORT"]) { $envValues["DB_PORT"] } else { "5432" }
$dbUser = if ($envValues["DB_USER"]) { $envValues["DB_USER"] } else { "postgres" }

Write-Host ""
Write-Host "===================================================="
Write-Host "DYNETIC WMS PRODUCTION READ-ONLY SMOKE CHECK"
Write-Host "===================================================="
Write-Host "Database .............. $DatabaseName"
Write-Host "Mode .................. READ ONLY"
Write-Host "Expected version ...... 0.2.0"
Write-Host "===================================================="

if ($DatabaseName -ne "fulfilment_prod") {
    throw "Safety stop: this script is intended only for fulfilment_prod."
}

$dbExists = Invoke-PsqlScalar @"
SELECT COUNT(*)
FROM pg_database
WHERE datname = '$DatabaseName';
"@
Assert-Equal "Production database exists" $dbExists "1"

$schemas = Invoke-PsqlScalar @"
SELECT COUNT(*)
FROM information_schema.schemata
WHERE schema_name IN ('core','interface','config','audit','api');
"@
Assert-Equal "Required schemas present" $schemas "5"

$version = Invoke-PsqlScalar @"
SELECT api.GET_SYSTEM_VERSION()->>'version';
"@
Assert-Equal "DYNETIC WMS version" $version "0.2.0"

$currentVersionRows = Invoke-PsqlScalar @"
SELECT COUNT(*)
FROM config.SYSTEM_VERSION
WHERE PRODUCT_CODE='DYNETIC_WMS'
  AND IS_CURRENT=TRUE
  AND VERSION_NUMBER='0.2.0';
"@
Assert-Equal "Current version row" $currentVersionRows "1"

$client = Invoke-PsqlScalar @"
SELECT COUNT(*)
FROM core.CLIENT
WHERE CLIENT_ID='FINATICS';
"@
Assert-Equal "FINATICS client present" $client "1"

$requiredTables = Invoke-PsqlScalar @"
SELECT COUNT(*)
FROM information_schema.tables
WHERE table_schema || '.' || table_name IN (
    'core.sku',
    'core.location',
    'core.inventory',
    'core.order_header',
    'core.order_line',
    'core.order_container',
    'core.allocation',
    'core.pick_task',
    'core.product',
    'core.product_variant',
    'core.customer_account',
    'core.payment_transaction',
    'interface.order_header_if',
    'interface.order_line_if',
    'config.system_setting',
    'config.system_version',
    'audit.payment_event',
    'audit.api_security_event'
);
"@
Assert-Equal "Required core/interface/config/audit tables" $requiredTables "18"

$requiredFunctions = Invoke-PsqlScalar @"
SELECT COUNT(DISTINCT n.nspname || '.' || p.proname)
FROM pg_proc p
JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname || '.' || p.proname IN (
    'core.allocate_order',
    'core.deallocate_order',
    'core.create_pick_tasks',
    'core.confirm_pick',
    'core.pack_order',
    'core.ship_container',
    'core.select_carrier',
    'interface.process_order_interface',
    'api.get_system_version',
    'api.get_catalog',
    'api.get_product',
    'api.search_catalog',
    'api.validate_basket',
    'api.quote_checkout',
    'api.create_pending_web_order',
    'api.create_payment_request',
    'api.process_payment_event',
    'api.get_payment_status'
);
"@
Assert-Equal "Required functions present" $requiredFunctions "18"

$requiredViews = Invoke-PsqlScalar @"
SELECT COUNT(*)
FROM information_schema.views
WHERE table_schema || '.' || table_name IN (
    'core.inventory_availability',
    'core.pick_work_queue',
    'core.order_fulfilment_workbench',
    'core.inventory_reservation_reconciliation',
    'core.shipment_work_queue',
    'core.carrier_selection_workbench',
    'core.delivery_hold_workbench',
    'core.container_merge_candidate_workbench',
    'api.catalog_variant_availability',
    'api.catalog_product_list'
);
"@
Assert-Equal "Required views present" $requiredViews "10"

$product = Invoke-PsqlScalar @"
SELECT COUNT(*)
FROM core.PRODUCT
WHERE CLIENT_ID='FINATICS'
  AND PRODUCT_ID='FRYTRAY001';
"@
Assert-Equal "FINatics fry tray product seed present" $product "1"

$variants = Invoke-PsqlScalar @"
SELECT COUNT(*)
FROM core.PRODUCT_VARIANT
WHERE CLIENT_ID='FINATICS'
  AND PRODUCT_ID='FRYTRAY001';
"@
Assert-Equal "FINatics fry tray variants" $variants "22"

$catalogueRows = Invoke-PsqlScalar @"
SELECT COUNT(*)
FROM api.CATALOG_PRODUCT_LIST
WHERE CLIENT_ID='FINATICS';
"@
Assert-Positive "Catalogue view returns rows" $catalogueRows

$orderRows = Invoke-PsqlScalar @"
SELECT COUNT(*)
FROM core.ORDER_HEADER
WHERE CLIENT_ID='FINATICS';
"@
Assert-Equal "Clean production order baseline" $orderRows "0"

$paymentRows = Invoke-PsqlScalar @"
SELECT COUNT(*)
FROM core.PAYMENT_TRANSACTION
WHERE CLIENT_ID='FINATICS';
"@
Assert-Equal "Clean production payment baseline" $paymentRows "0"

$inventoryRows = Invoke-PsqlScalar @"
SELECT COUNT(*)
FROM core.INVENTORY
WHERE CLIENT_ID='FINATICS';
"@
Assert-Equal "Clean production inventory baseline" $inventoryRows "0"

$interfaceRows = Invoke-PsqlScalar @"
SELECT
    (SELECT COUNT(*)
       FROM interface.ORDER_HEADER_IF
      WHERE CLIENT_ID='FINATICS')
  + (SELECT COUNT(*)
       FROM interface.ORDER_LINE_IF l
       JOIN interface.ORDER_HEADER_IF h
         ON h.INTERFACE_ID = l.INTERFACE_ID
      WHERE h.CLIENT_ID='FINATICS');
"@
Assert-Equal "Clean production interface baseline" $interfaceRows "0"

Write-Host ""
Write-Host "===================================================="
Write-Host "PRODUCTION SMOKE CHECK PASSED"
Write-Host "===================================================="
Write-Host "Database .............. fulfilment_prod"
Write-Host "Version ............... 0.2.0"
Write-Host "FINATICS client ....... PASS"
Write-Host "Schema contract ....... PASS"
Write-Host "Catalogue seed ........ PASS"
Write-Host "Operational data ...... CLEAN"
Write-Host "Write operations ...... NONE"
Write-Host "===================================================="
