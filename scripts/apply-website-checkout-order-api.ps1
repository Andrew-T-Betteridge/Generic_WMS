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

Invoke-SqlFile "database\migrations\0013_website_checkout_order_api_v1.sql"
Invoke-SqlFile "database\indexes\009_website_checkout_indexes.sql"
Invoke-SqlFile "database\functions\interface\PROCESS_ORDER_INTERFACE.sql"
Invoke-SqlFile "database\functions\api\VALIDATE_BASKET.sql"
Invoke-SqlFile "database\functions\api\QUOTE_CHECKOUT.sql"
Invoke-SqlFile "database\functions\api\SUBMIT_WEB_ORDER.sql"
Invoke-SqlFile "database\functions\api\GET_ORDER_STATUS.sql"

Write-Host ""
Write-Host "Website Checkout & Order API V1 applied successfully."
