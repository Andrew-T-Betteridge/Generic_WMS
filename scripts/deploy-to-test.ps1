param([string]$Database='fulfilment_test',[string]$DbUser='postgres',[switch]$KeepDatabase)
$ErrorActionPreference='Stop'
. "$PSScriptRoot\environment-common.ps1"
Assert-DyneticDatabaseName -Database $Database -Environment TEST
if(-not $KeepDatabase){ & "$PSScriptRoot\create-test-db.ps1" -Database $Database -DbUser $DbUser }
& "$PSScriptRoot\build-database.ps1" -Database $Database -DbUser $DbUser
if($LASTEXITCODE -ne 0){throw 'TEST deployment failed.'}
& "$PSScriptRoot\test-database-regression.ps1" -Database $Database -DbUser $DbUser
if($LASTEXITCODE -ne 0){throw 'TEST regression failed.'}
Write-Host 'DYNETIC WMS TEST deployment + regression passed.'
