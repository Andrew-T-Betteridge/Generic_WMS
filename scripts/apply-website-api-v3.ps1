param([string]$Database="fulfilment_dev",[string]$DbUser="postgres")
$ErrorActionPreference="Stop"
$Psql="C:\Program Files\PostgreSQL\18\bin\psql.exe"
$Root=(Resolve-Path "$PSScriptRoot\..").Path

$Files=@(
 "database\migrations\0016_website_api_v3_payments_accounts_security.sql",
 "database\functions\api\UPSERT_ACCOUNT_IDENTITY.sql",
 "database\functions\api\GET_ACCOUNT.sql",
 "database\functions\api\SAVE_ACCOUNT_ADDRESS.sql",
 "database\functions\api\GET_ACCOUNT_ADDRESSES.sql",
 "database\functions\api\SET_PRODUCT_FAVOURITE.sql",
 "database\functions\api\GET_PRODUCT_FAVOURITES.sql",
 "database\functions\api\GET_ACCOUNT_ORDERS.sql",
 "database\functions\api\GET_ACCOUNT_INTERESTS.sql",
 "database\functions\api\GET_ACCOUNT_RESERVATIONS.sql",
 "database\functions\api\CLAIM_ORDER_ACCOUNT.sql",
 "database\functions\api\CREATE_PENDING_WEB_ORDER.sql",
 "database\functions\api\EXPIRE_PENDING_PAYMENT_ORDERS.sql",
 "database\functions\api\CREATE_PAYMENT_REQUEST.sql",
 "database\functions\api\SET_PAYMENT_PROVIDER_REFERENCE.sql",
 "database\functions\api\PROCESS_PAYMENT_EVENT.sql",
 "database\functions\api\GET_PAYMENT_STATUS.sql",
 "database\indexes\011_website_api_v3_indexes.sql",
 "database\migrations\0017_dynetic_wms_0_2_0.sql"
)

foreach($File in $Files){
    Write-Host "Applying $File"
    & $Psql -U $DbUser -d $Database -v ON_ERROR_STOP=1 -P pager=off -f (Join-Path $Root $File)
    if($LASTEXITCODE -ne 0){throw "Website/API V3 failed: $File"}
}
Write-Host "DYNETIC WMS Website/API V3 applied successfully."
