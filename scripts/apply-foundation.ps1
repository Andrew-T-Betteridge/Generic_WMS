\
param(
    [string]$Database = "fulfilment_dev",
    [string]$User = "postgres"
)

$ErrorActionPreference = "Stop"

$files = @(
    "database/schemas/001_core.sql",
    "database/schemas/002_iface.sql",
    "database/schemas/003_config.sql",
    "database/schemas/004_audit.sql",
    "database/tables/core/CLIENT.sql",
    "database/tables/config/CARRIER.sql",
    "database/tables/config/CARRIER_SERVICE.sql",
    "database/tables/config/CARRIER_SELECTION_RULE.sql",
    "database/tables/config/MERGE_RULE.sql",
    "database/tables/iface/INTERFACE_ERROR.sql",
    "database/tables/audit/PROCESSING_LOG.sql",
    "database/indexes/001_config_indexes.sql",
    "database/seed/001_client.sql"
)

foreach ($file in $files) {
    Write-Host "Applying $file"
    psql -U $User -d $Database -f $file
}
