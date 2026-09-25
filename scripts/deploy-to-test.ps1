param(
    [string]$Database='fulfilment_test',
    [string]$DbUser='postgres'
)

$ErrorActionPreference='Stop'

. "$PSScriptRoot\environment-common.ps1"

Assert-DyneticDatabaseName `
    -Database $Database `
    -Environment TEST

Write-Host '===================================================='
Write-Host 'DYNETIC WMS STRICT TEST DEPLOYMENT'
Write-Host '===================================================='

Write-Host '[1/3] Recreating isolated TEST database...'
& "$PSScriptRoot\create-test-db.ps1" `
    -Database $Database `
    -DbUser $DbUser

if($LASTEXITCODE -ne 0){
    throw 'TEST database creation failed.'
}

Write-Host '[2/3] Fresh bootstrapping repository into TEST...'
& "$PSScriptRoot\Bootstrap-FreshDatabase.ps1" `
    -Target TEST `
    -Database $Database `
    -DbUser $DbUser

if($LASTEXITCODE -ne 0){
    throw 'TEST fresh bootstrap failed.'
}

Write-Host '[3/3] Running database regression...'
& "$PSScriptRoot\test-database-regression.ps1" `
    -Database $Database `
    -DbUser $DbUser

if($LASTEXITCODE -ne 0){
    throw 'TEST regression failed.'
}

Write-Host ''
Write-Host 'DYNETIC WMS STRICT TEST DEPLOYMENT PASSED.'
