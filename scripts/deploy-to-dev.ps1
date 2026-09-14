param([string]$Database='fulfilment_dev',[string]$DbUser='postgres')
$ErrorActionPreference='Stop'
. "$PSScriptRoot\environment-common.ps1"
Assert-DyneticDatabaseName -Database $Database -Environment DEVELOPMENT
& "$PSScriptRoot\build-database.ps1" -Database $Database -DbUser $DbUser
if($LASTEXITCODE -ne 0){throw 'DEV deployment failed.'}
Write-Host 'DYNETIC WMS DEV deployment passed.'
