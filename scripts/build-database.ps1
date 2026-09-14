param([string]$Database="fulfilment_dev",[string]$DbUser="postgres")
$ErrorActionPreference="Stop"

& "$PSScriptRoot\apply-foundation.ps1" -Database $Database -DbUser $DbUser
if($LASTEXITCODE -ne 0){throw "Foundation build failed."}
& "$PSScriptRoot\apply-core.ps1" -Database $Database -DbUser $DbUser
if($LASTEXITCODE -ne 0){throw "Core build failed."}
& "$PSScriptRoot\apply-supporting-tables.ps1" -Database $Database -DbUser $DbUser
if($LASTEXITCODE -ne 0){throw "Supporting build failed."}
& "$PSScriptRoot\apply-allocation.ps1" -Database $Database -DbUser $DbUser
if($LASTEXITCODE -ne 0){throw "Allocation build failed."}
& "$PSScriptRoot\apply-warehouse-execution.ps1" -Database $Database -DbUser $DbUser
if($LASTEXITCODE -ne 0){throw "Warehouse execution build failed."}
& "$PSScriptRoot\apply-carrier-selection.ps1" -Database $Database -DbUser $DbUser
if($LASTEXITCODE -ne 0){throw "Carrier selection build failed."}
& "$PSScriptRoot\apply-fulfilment-holds.ps1" -Database $Database -DbUser $DbUser
if($LASTEXITCODE -ne 0){throw "Fulfilment holds build failed."}
& "$PSScriptRoot\apply-merge-consolidation.ps1" -Database $Database -DbUser $DbUser
if($LASTEXITCODE -ne 0){throw "Merge / consolidation build failed."}
& "$PSScriptRoot\apply-website-catalogue.ps1" -Database $Database -DbUser $DbUser
if($LASTEXITCODE -ne 0){throw "Website catalogue build failed."}
& "$PSScriptRoot\apply-website-checkout-order-api.ps1" -Database $Database -DbUser $DbUser
if($LASTEXITCODE -ne 0){throw "Website checkout/order API build failed."}
& "$PSScriptRoot\apply-website-domain-v2.ps1" -Database $Database -DbUser $DbUser
if($LASTEXITCODE -ne 0){throw "Website Domain V2 build failed."}
& "$PSScriptRoot\apply-system-version.ps1" -Database $Database -DbUser $DbUser
if($LASTEXITCODE -ne 0){throw "DYNETIC WMS system version build failed."}
& "$PSScriptRoot\apply-website-api-v3.ps1" -Database $Database -DbUser $DbUser
if($LASTEXITCODE -ne 0){throw "Website/API V3 build failed."}

Write-Host ""
Write-Host "DYNETIC WMS database build completed successfully."
