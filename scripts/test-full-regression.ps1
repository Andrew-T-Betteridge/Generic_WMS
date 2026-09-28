param(
    [string]$TestDatabase = 'fulfilment_test',
    [string]$DbUser = 'postgres',
    [string]$HostName = 'localhost',
    [int]$Port = 5432,
    [string]$BaseUrl = 'http://localhost:3101',
    [switch]$SkipApi
)

# DYNETIC_TEST_WRAPPER_GUARD_BEGIN
. "$PSScriptRoot\Test-Safety.ps1"
$null = Assert-DyneticTestScriptSafety `
    -ScriptPath $MyInvocation.MyCommand.Path `
    -BoundParameters $PSBoundParameters
# DYNETIC_TEST_WRAPPER_GUARD_END

$ErrorActionPreference = 'Stop'

. "$PSScriptRoot\Test-Safety.ps1"

$null = Assert-DyneticNonProductionApi `
    -BaseUrl $BaseUrl

. "$PSScriptRoot\environment-common.ps1"

Assert-DyneticDatabaseName `
    -Database $TestDatabase `
    -Environment TEST

$allowedTestHosts = @(
    'localhost',
    '127.0.0.1',
    '::1'
)

if($HostName -notin $allowedTestHosts){
    throw "FULL TEST gate blocked non-local PostgreSQL host '$HostName'."
}

if($Port -ne 5432){
    throw "FULL TEST gate requires PostgreSQL port 5432."
}

$start = Get-Date

Write-Host '===================================================='
Write-Host 'DYNETIC WMS STRICT TEST RELEASE GATE'
Write-Host '===================================================='
Write-Host "Database: $HostName`:$Port / $TestDatabase"
Write-Host "API:      $BaseUrl"
Write-Host ''

Write-Host '[1/4] API environment safety regression...'

& "$PSScriptRoot\test-api-environment-safety.ps1"

if(-not $?){
    throw 'API environment safety regression failed.'
}

Write-Host ''
Write-Host '[2/4] API TypeScript validation...'

$apiPath = Join-Path `
    (Split-Path $PSScriptRoot -Parent) `
    'apps\api'

Push-Location $apiPath

try {
    & npm.cmd run typecheck

    if($LASTEXITCODE -ne 0){
        throw 'API typecheck failed.'
    }
}
finally {
    Pop-Location
}

Write-Host ''
Write-Host '[3/4] Clean isolated TEST database deployment and regression...'

& "$PSScriptRoot\deploy-to-test.ps1" `
    -Database $TestDatabase `
    -DbUser $DbUser `
    -HostName $HostName `
    -Port $Port

if(-not $?){
    throw 'Strict TEST database deployment failed.'
}

if($SkipApi){
    Write-Host ''
    Write-Host '[4/4] API/Auth0 regression SKIPPED by explicit -SkipApi.'
}
else {
    Write-Host ''
    Write-Host '[4/4] TEST API/Auth0 regression...'

    & "$PSScriptRoot\test-api-regression.ps1" `
        -BaseUrl $BaseUrl

    if(-not $?){
        throw 'TEST API/Auth0 regression failed.'
    }
}

$elapsed = (Get-Date) - $start

Write-Host ''
Write-Host '===================================================='
Write-Host 'DYNETIC WMS STRICT TEST RELEASE GATE PASSED'
Write-Host '===================================================='
Write-Host 'API environment safety ....... PASS'
Write-Host 'API TypeScript validation .... PASS'
Write-Host 'Clean TEST deployment ........ PASS'
Write-Host 'Database regression .......... PASS'

if($SkipApi){
    Write-Host 'API/Auth0 regression ......... SKIPPED'
}
else {
    Write-Host 'API/Auth0 regression ......... PASS'
}

Write-Host ('Elapsed ...................... {0:mm\:ss}' -f $elapsed)
Write-Host '===================================================='
