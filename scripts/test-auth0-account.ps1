param(
    [string]$BaseUrl = "http://localhost:3001",
    [string]$AccessToken = ""
)
# DYNETIC_TEST_WRAPPER_GUARD_BEGIN
. "$PSScriptRoot\Test-Safety.ps1"
$null = Assert-DyneticTestScriptSafety -ScriptPath $MyInvocation.MyCommand.Path -BoundParameters $PSBoundParameters
# DYNETIC_TEST_WRAPPER_GUARD_END


$ErrorActionPreference = "Stop"

. "$PSScriptRoot\Test-Safety.ps1"
$null = Assert-DyneticNonProductionApi -BaseUrl $BaseUrl
if (-not $AccessToken) {
    $secure = Read-Host "Paste an Auth0 USER access token" -AsSecureString
    $ptr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
    try {
        $AccessToken = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($ptr)
    }
    finally {
        [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($ptr)
    }
}

if (-not $AccessToken) {
    throw "No access token supplied."
}

$headers = @{
    Authorization = "Bearer $AccessToken"
}

Write-Host ""
Write-Host "===================================================="
Write-Host "DYNETIC WMS AUTH0 ACCOUNT SMOKE TEST"
Write-Host "===================================================="

$account = Invoke-RestMethod `
    -Uri "$BaseUrl/api/account" `
    -Method Get `
    -Headers $headers

Write-Host "[PASS] Auth0 JWT accepted by DYNETIC WMS"
Write-Host "[PASS] /api/account returned an account"
Write-Host ""
Write-Host "Account response:"
$account | ConvertTo-Json -Depth 8

Write-Host ""
Write-Host "===================================================="
Write-Host "AUTH0 -> JWT -> DYNETIC ACCOUNT TEST PASSED"
Write-Host "===================================================="
