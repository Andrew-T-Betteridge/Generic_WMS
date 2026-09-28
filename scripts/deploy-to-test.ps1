param(
    [string]$Database='fulfilment_test',
    [string]$DbUser='postgres',
    [string]$HostName='localhost',
    [int]$Port=5432
)

$ErrorActionPreference='Stop'

. "$PSScriptRoot\environment-common.ps1"

$allowedTestHosts=@('localhost','127.0.0.1','::1')

if($HostName -notin $allowedTestHosts){
    throw "TEST deployment safety guard blocked non-local PostgreSQL host '$HostName'."
}

Assert-DyneticDatabaseName `
    -Database $Database `
    -Environment TEST

Write-Host '===================================================='
Write-Host 'DYNETIC WMS STRICT TEST DEPLOYMENT'
Write-Host "PostgreSQL: $HostName`:$Port / $Database"
Write-Host '===================================================='

Write-Host '[1/3] Recreating isolated TEST database...'
& "$PSScriptRoot\create-test-db.ps1" `
    -Database $Database `
    -DbUser $DbUser `
    -HostName $HostName `
    -Port $Port

Write-Host '[2/3] Fresh bootstrapping repository into TEST...'
& "$PSScriptRoot\Bootstrap-FreshDatabase.ps1" `
    -Target TEST `
    -Database $Database `
    -HostName $HostName `
    -Port $Port `
    -DbUser $DbUser

Write-Host '[3/3] Running database regression...'
& "$PSScriptRoot\test-database-regression.ps1" `
    -Database $Database `
    -DbUser $DbUser `
    -HostName $HostName `
    -Port $Port

Write-Host ''
Write-Host 'DYNETIC WMS STRICT TEST DEPLOYMENT PASSED.'
