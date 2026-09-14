param([string]$Database="fulfilment_dev",[string]$DbUser="postgres")
$ErrorActionPreference="Stop"
$Psql="C:\Program Files\PostgreSQL\18\bin\psql.exe"
$Root=(Resolve-Path "$PSScriptRoot\..").Path

$Files=@(
 "database\migrations\0015_dynetic_wms_system_version.sql",
 "database\functions\api\GET_SYSTEM_VERSION.sql"
)

foreach($File in $Files){
    Write-Host "Applying $File"
    & $Psql -U $DbUser -d $Database -v ON_ERROR_STOP=1 -f (Join-Path $Root $File)
    if($LASTEXITCODE -ne 0){throw "DYNETIC WMS system version failed: $File"}
}

Write-Host "DYNETIC WMS system version applied successfully."
