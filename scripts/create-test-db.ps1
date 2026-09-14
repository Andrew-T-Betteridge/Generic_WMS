param([string]$Database='fulfilment_test',[string]$DbUser='postgres',[switch]$KeepExisting)
$ErrorActionPreference='Stop'
. "$PSScriptRoot\environment-common.ps1"
Assert-DyneticDatabaseName -Database $Database -Environment TEST
if (-not $KeepExisting) { Invoke-DyneticPsql -Database postgres -DbUser $DbUser -Command ('DROP DATABASE IF EXISTS "{0}" WITH (FORCE);' -f $Database) }
$exists = (& $script:DyneticPsql -U $DbUser -d postgres -Atqc "SELECT 1 FROM pg_database WHERE datname='$Database';") -eq '1'
if (-not $exists) { Invoke-DyneticPsql -Database postgres -DbUser $DbUser -Command ('CREATE DATABASE "{0}";' -f $Database) }
Write-Host "DYNETIC WMS TEST database ready: $Database"
