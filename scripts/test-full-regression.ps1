param(
 [string]$TestDatabase='fulfilment_test',[string]$DbUser='postgres',
 [switch]$IncludeHttp,[string]$BaseUrl='http://localhost:3001',
 [string]$DevSecret='dynetic-local-test-secret-change-me',[switch]$KeepTestDatabase
)
$ErrorActionPreference='Stop'
. "$PSScriptRoot\environment-common.ps1"
Assert-DyneticDatabaseName -Database $TestDatabase -Environment TEST
$start=Get-Date
Write-Host '===================================================='
Write-Host 'DYNETIC WMS FULL REGRESSION SUITE'
Write-Host '===================================================='
Write-Host '[1/3] Recreating TEST database...'
& "$PSScriptRoot\create-test-db.ps1" -Database $TestDatabase -DbUser $DbUser
Write-Host '[2/3] Clean building repository into TEST...'
& "$PSScriptRoot\build-database.ps1" -Database $TestDatabase -DbUser $DbUser
if($LASTEXITCODE -ne 0){throw 'Clean TEST build failed.'}
Write-Host '[3/3] Running database regression...'
& "$PSScriptRoot\test-database-regression.ps1" -Database $TestDatabase -DbUser $DbUser
if($LASTEXITCODE -ne 0){throw 'Database regression failed.'}
if($IncludeHttp){
 Write-Host '[HTTP] Running API regression against the currently running API.'
 Write-Host 'NOTE: the API must itself be configured to point at the intended TEST database before using -IncludeHttp.'
 & "$PSScriptRoot\test-api-regression.ps1" -BaseUrl $BaseUrl -DevSecret $DevSecret
 if($LASTEXITCODE -ne 0){throw 'HTTP regression failed.'}
}
$elapsed=(Get-Date)-$start
Write-Host ''
Write-Host '===================================================='
Write-Host 'DYNETIC WMS FULL REGRESSION SUITE PASSED'
Write-Host '===================================================='
Write-Host 'Clean TEST build ............ PASS'
Write-Host 'Existing regression ......... PASS'
Write-Host 'Schema contract ............. PASS'
Write-Host 'Interface negative cases .... PASS'
Write-Host 'Inventory reconciliation .... PASS'
Write-Host 'Reservation expiry .......... PASS'
Write-Host 'Payment failure/expiry ...... PASS'
Write-Host 'Payment security/idempotency  PASS'
$httpStatus = if($IncludeHttp){'HTTP/API contract ............ PASS'}else{'HTTP/API contract ............ SKIPPED (use -IncludeHttp)'}
Write-Host $httpStatus
Write-Host ('Elapsed ...................... {0:mm\:ss}' -f $elapsed)
Write-Host '===================================================='
if(-not $KeepTestDatabase){ Write-Host "TEST database retained as '$TestDatabase' for deployment/UAT. Use create-test-db.ps1 to rebuild it." }
