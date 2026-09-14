param([string]$Database='fulfilment_prod',[string]$DbUser='postgres',[switch]$IUnderstandThisCreatesProduction)
$ErrorActionPreference='Stop'
. "$PSScriptRoot\environment-common.ps1"
Assert-DyneticDatabaseName -Database $Database -Environment PRODUCTION
if (-not $IUnderstandThisCreatesProduction) { throw 'PRODUCTION GUARD: rerun with -IUnderstandThisCreatesProduction. This script never drops an existing PROD database.' }
$exists = (& $script:DyneticPsql -U $DbUser -d postgres -Atqc "SELECT 1 FROM pg_database WHERE datname='$Database';") -eq '1'
if ($exists) { Write-Host "PROD database already exists; nothing changed: $Database"; exit 0 }
Invoke-DyneticPsql -Database postgres -DbUser $DbUser -Command ('CREATE DATABASE "{0}";' -f $Database)
Write-Host "DYNETIC WMS PROD database created: $Database"
