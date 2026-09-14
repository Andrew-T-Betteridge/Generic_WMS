param(
    [string]$BaseUrl = 'http://localhost:3001',
    [string]$DevSecret = 'dynetic-local-test-secret-change-me'
)

$ErrorActionPreference = 'Stop'

Write-Host '[API TEST] V3 HTTP authentication/security contract'

& "$PSScriptRoot\test-website-api-v3-http.ps1" `
    -BaseUrl $BaseUrl `
    -DevSecret $DevSecret

Write-Host 'DYNETIC WMS API REGRESSION PASSED.'