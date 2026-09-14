param([string]$Database="fulfilment_dev",[string]$DbUser="postgres")
$ErrorActionPreference="Stop"
$Psql="C:\Program Files\PostgreSQL\18\bin\psql.exe"
$Root=(Resolve-Path "$PSScriptRoot\..").Path

$Files=@(
 "database\migrations\0014_website_domain_v2.sql",
 "database\functions\interface\PROCESS_ORDER_INTERFACE.sql",

 # V2 catalogue objects are deliberately applied only AFTER migration 0014.
 "database\views\api\CATALOG_VARIANT_AVAILABILITY_V2.sql",
 "database\views\api\CATALOG_PRODUCT_LIST_V2.sql",
 "database\functions\api\GET_PRODUCT_MEDIA.sql",
 "database\functions\api\GET_CATEGORIES.sql",
 "database\functions\api\GET_CATALOG_V2.sql",
 "database\functions\api\GET_PRODUCT_V2.sql",
 "database\functions\api\GET_AFFILIATE_LINKS.sql",
 "database\functions\api\SEARCH_CATALOG.sql",

 "database\functions\api\VALIDATE_BASKET.sql",
 "database\functions\api\CREATE_CUSTOMER_INTEREST.sql",
 "database\functions\api\GET_INTEREST_SUMMARY.sql",
 "database\functions\api\GET_INTEREST_CONTACTS.sql",
 "database\functions\api\MARK_INTEREST_NOTIFIED.sql",
 "database\functions\api\GET_STOCK_RESERVATION.sql",
 "database\functions\api\CREATE_STOCK_RESERVATION.sql",
 "database\functions\api\RELEASE_STOCK_RESERVATION.sql",
 "database\functions\api\EXPIRE_STOCK_RESERVATIONS.sql",
 "database\functions\api\RECORD_AFFILIATE_CLICK.sql",
 "database\functions\api\GET_AFFILIATE_DEMAND.sql",
 "database\functions\api\GET_DELIVERY_OPTIONS.sql",
 "database\functions\api\VALIDATE_PROMOTION.sql",
 "database\functions\api\GET_GIFT_CARD_BALANCE.sql",
 "database\functions\api\SUBMIT_PRODUCT_REVIEW.sql",
 "database\functions\api\GET_PRODUCT_REVIEWS.sql",
 "database\functions\api\MODERATE_PRODUCT_REVIEW.sql",
 "database\functions\api\SET_CONTACT_PREFERENCE.sql",
 "database\functions\api\PREPARE_PAYMENT.sql",
 "database\functions\api\QUOTE_CHECKOUT.sql",
 "database\functions\api\SUBMIT_WEB_ORDER.sql",
 "database\functions\api\SUBMIT_RESERVED_WEB_ORDER.sql",
 "database\indexes\010_website_domain_v2_indexes.sql"
)

foreach($File in $Files){
    Write-Host "Applying $File"
    & $Psql -U $DbUser -d $Database -v ON_ERROR_STOP=1 -f (Join-Path $Root $File)
    if($LASTEXITCODE -ne 0){throw "Website Domain V2 failed: $File"}
}
Write-Host "Website Domain V2 applied successfully."
