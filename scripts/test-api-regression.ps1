param(
    [string]$BaseUrl = 'http://localhost:3001',
    [string]$DevSecret = 'dynetic-local-test-secret-change-me'
)
# DYNETIC_TEST_WRAPPER_GUARD_BEGIN
. "$PSScriptRoot\Test-Safety.ps1"
$null = Assert-DyneticTestScriptSafety -ScriptPath $MyInvocation.MyCommand.Path -BoundParameters $PSBoundParameters
# DYNETIC_TEST_WRAPPER_GUARD_END


$ErrorActionPreference = 'Stop'

. "$PSScriptRoot\Test-Safety.ps1"
$null = Assert-DyneticNonProductionApi -BaseUrl $BaseUrl
Write-Host '[API TEST] V3 HTTP authentication/security contract'

& "$PSScriptRoot\test-website-api-v3-http.ps1" `
    -BaseUrl $BaseUrl `
    -DevSecret $DevSecret

Write-Host 'DYNETIC WMS API REGRESSION PASSED.'