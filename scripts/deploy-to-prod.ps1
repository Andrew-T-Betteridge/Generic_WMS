param(
 [string]$Database='fulfilment_prod',[string]$DbUser='postgres',
 [switch]$ApprovedForProduction,[switch]$TestRegressionPassed
)
$ErrorActionPreference='Stop'
. "$PSScriptRoot\environment-common.ps1"
Assert-DyneticDatabaseName -Database $Database -Environment PRODUCTION
if(-not $ApprovedForProduction){throw 'PRODUCTION GUARD: -ApprovedForProduction is required.'}
if(-not $TestRegressionPassed){throw 'PRODUCTION GUARD: confirm the exact release passed TEST using -TestRegressionPassed.'}
$exists = (& $script:DyneticPsql -U $DbUser -d postgres -Atqc "SELECT 1 FROM pg_database WHERE datname='$Database';") -eq '1'
if(-not $exists){throw "PRODUCTION GUARD: $Database does not exist. Create it explicitly first."}
Write-Host 'PRODUCTION GUARD PASSED. Applying repository build/migrations to existing PROD. No database drop will occur.'
& "$PSScriptRoot\build-database.ps1" -Database $Database -DbUser $DbUser
if($LASTEXITCODE -ne 0){throw 'PROD deployment failed.'}
Write-Host 'DYNETIC WMS PROD deployment completed. Run production smoke checks before opening traffic.'
