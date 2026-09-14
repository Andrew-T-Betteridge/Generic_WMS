param(
    [Parameter(Mandatory=$true)]
    [string]$Auth0Domain,

    [string]$Audience = "https://test-api.finaticsaquatics.co.uk"
)

$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
$template = Join-Path $repoRoot "config\environments\test.auth0.env.example"
$output = Join-Path $repoRoot "config\environments\test.auth0.env"

if (-not (Test-Path $template)) {
    throw "Template not found: $template"
}

$domain = $Auth0Domain.Trim()
$domain = $domain -replace '^https?://',''
$domain = $domain.TrimEnd('/')

if (-not $domain.Contains(".")) {
    throw "Auth0Domain does not look valid. Example format: tenant-name.uk.auth0.com"
}

$issuer = "https://$domain/"
$jwks = "https://$domain/.well-known/jwks.json"

$content = Get-Content $template -Raw
$content = $content.Replace("AUTH_ISSUER=", "AUTH_ISSUER=$issuer")
$content = $content.Replace("AUTH_AUDIENCE=https://test-api.finaticsaquatics.co.uk", "AUTH_AUDIENCE=$Audience")
$content = $content.Replace("AUTH_JWKS_URL=", "AUTH_JWKS_URL=$jwks")

Set-Content -Path $output -Value $content -Encoding UTF8

Write-Host ""
Write-Host "===================================================="
Write-Host "DYNETIC WMS AUTH0 TEST CONFIG CREATED"
Write-Host "===================================================="
Write-Host "File .................. config\environments\test.auth0.env"
Write-Host "Provider .............. AUTH0"
Write-Host "Issuer ................ $issuer"
Write-Host "Audience .............. $Audience"
Write-Host "JWKS .................. $jwks"
Write-Host "Database .............. fulfilment_test"
Write-Host "===================================================="
Write-Host ""
Write-Host "Next: copy your existing TEST-only ORDER_ACCESS_TOKEN_SECRET and"
Write-Host "Stripe TEST values into test.auth0.env if required."
Write-Host "Do not put production/live Stripe credentials in this file."
