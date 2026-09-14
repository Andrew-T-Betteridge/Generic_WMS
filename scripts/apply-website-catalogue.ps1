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

Invoke-SqlFile "database\migrations\0012_website_catalogue_v1.sql"
Invoke-SqlFile "database\tables\core\PRODUCT_CATEGORY.sql"
Invoke-SqlFile "database\tables\core\PRODUCT.sql"
Invoke-SqlFile "database\tables\core\PRODUCT_VARIANT.sql"
Invoke-SqlFile "database\indexes\008_website_catalogue_indexes.sql"
Invoke-SqlFile "database\views\api\CATALOG_VARIANT_AVAILABILITY.sql"
Invoke-SqlFile "database\views\api\CATALOG_PRODUCT_LIST.sql"
Invoke-SqlFile "database\functions\api\GET_CATALOG.sql"
Invoke-SqlFile "database\functions\api\GET_PRODUCT.sql"
Invoke-SqlFile "database\seeds\001_finatics_fry_tray.sql"

Write-Host ""
Write-Host "Website Catalogue V1 applied successfully."
