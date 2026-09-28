param(
    [string]$BaseUrl = 'http://localhost:3101',
    [string]$DevSecret = 'dynetic-local-test-secret-change-me',
    [string]$AccessToken = ''
)

# DYNETIC_TEST_WRAPPER_GUARD_BEGIN
. "$PSScriptRoot\Test-Safety.ps1"
$null = Assert-DyneticTestScriptSafety `
    -ScriptPath $MyInvocation.MyCommand.Path `
    -BoundParameters $PSBoundParameters
# DYNETIC_TEST_WRAPPER_GUARD_END

$ErrorActionPreference = 'Stop'

. "$PSScriptRoot\Test-Safety.ps1"

$environment = Assert-DyneticNonProductionApi -BaseUrl $BaseUrl

$health = Invoke-RestMethod `
    -Method Get `
    -Uri "$($BaseUrl.TrimEnd('/'))/health"

if($health.service -ne 'DYNETIC WMS API'){
    throw "Unexpected health service name."
}

Write-Host "[PASS] API health verified as $environment"

Write-Host '[API TEST] Public catalogue'

$catalog = Invoke-RestMethod `
    -Method Get `
    -Uri "$($BaseUrl.TrimEnd('/'))/api/catalog/products"

if(-not $catalog -or $catalog.Count -lt 1){
    throw "Catalogue unavailable."
}

Write-Host '[PASS] Public catalogue available'

if($environment -eq 'DEV'){
    Write-Host '[API TEST] DEV HS256 authentication/security contract'

    & "$PSScriptRoot\test-website-api-v3-http.ps1" `
        -BaseUrl $BaseUrl `
        -DevSecret $DevSecret

    Write-Host 'DYNETIC WMS DEV API REGRESSION PASSED.'
    exit 0
}

if($environment -ne 'TEST'){
    throw "Unsupported API regression environment '$environment'."
}

Write-Host '[API TEST] TEST OIDC authentication/security contract'

function ConvertTo-Base64Url([byte[]]$Bytes){
    [Convert]::ToBase64String($Bytes).
        TrimEnd('=').
        Replace('+','-').
        Replace('/','_')
}

function ConvertTo-JsonBytes($Object){
    [Text.Encoding]::UTF8.GetBytes(
        ($Object | ConvertTo-Json -Compress)
    )
}

function New-ForgedHs256Token {
    $secret = 'this-token-must-never-be-accepted-by-oidc'
    $now = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()

    $header = ConvertTo-Base64Url (
        ConvertTo-JsonBytes @{
            alg='HS256'
            typ='JWT'
        }
    )

    $payload = ConvertTo-Base64Url (
        ConvertTo-JsonBytes @{
            sub='forged-test-user'
            email='forged@example.invalid'
            email_verified=$true
            iat=$now
            exp=$now+3600
        }
    )

    $unsigned="$header.$payload"

    $hmac=[System.Security.Cryptography.HMACSHA256]::new(
        [Text.Encoding]::UTF8.GetBytes($secret)
    )

    try {
        $signature = ConvertTo-Base64Url (
            $hmac.ComputeHash(
                [Text.Encoding]::UTF8.GetBytes($unsigned)
            )
        )
    }
    finally {
        $hmac.Dispose()
    }

    return "$unsigned.$signature"
}

$forgedToken = New-ForgedHs256Token

try {
    Invoke-RestMethod `
        -Method Get `
        -Uri "$($BaseUrl.TrimEnd('/'))/api/account" `
        -Headers @{Authorization="Bearer $forgedToken"} |
        Out-Null

    throw "SECURITY FAILURE: OIDC API accepted a forged HS256 token."
}
catch {
    if($_.Exception.Message -like 'SECURITY FAILURE:*'){
        throw
    }

    $status = $null

    try {
        $status = [int]$_.Exception.Response.StatusCode
    }
    catch {}

    if($status -and ($status -lt 400 -or $status -ge 500)){
        throw "Unexpected status $status while testing forged OIDC token."
    }

    Write-Host '[PASS] OIDC API rejected forged HS256 token'
}

Write-Host '[API TEST] Genuine Auth0 user token'

if($AccessToken){
    & "$PSScriptRoot\test-auth0-account.ps1" `
        -BaseUrl $BaseUrl `
        -AccessToken $AccessToken
}
else {
    & "$PSScriptRoot\test-auth0-account.ps1" `
        -BaseUrl $BaseUrl
}

Write-Host ''
Write-Host 'DYNETIC WMS TEST OIDC API REGRESSION PASSED.'
