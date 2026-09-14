param([string]$Database='fulfilment_dev',[string]$DbUser='postgres',[switch]$Recreate)
$ErrorActionPreference='Stop'
. "$PSScriptRoot\environment-common.ps1"
Assert-DyneticDatabaseName -Database $Database -Environment DEVELOPMENT
$exists = (& $script:DyneticPsql -U $DbUser -d postgres -Atqc "SELECT 1 FROM pg_database WHERE datname='$Database';") -eq '1'
if ($exists -and -not $Recreate) { Write-Host "DEV database already exists: $Database"; exit 0 }
if ($exists) { Invoke-DyneticPsql -Database postgres -DbUser $DbUser -Command ('DROP DATABASE IF EXISTS "{0}" WITH (FORCE);' -f $Database) }
Invoke-DyneticPsql -Database postgres -DbUser $DbUser -Command ('CREATE DATABASE "{0}";' -f $Database)
Write-Host "DYNETIC WMS DEV database ready: $Database"
