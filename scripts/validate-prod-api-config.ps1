param(
    [string]$EnvironmentFile = ""
)

$ErrorActionPreference = "Stop"

function Read-DotEnv([string]$Path) {
    $values = @{}
    if (-not (Test-Path $Path)) {
        throw "Production environment file not found: $Path"
    }

    foreach ($line in Get-Content $Path) {
        $trimmed = $line.Trim()
        if (-not $trimmed -or $trimmed.StartsWith("#")) { continue }
        $eq = $trimmed.IndexOf("=")
        if ($eq -lt 1) { continue }
        $key = $trimmed.Substring(0,$eq).Trim()
        $value = $trimmed.Substring($eq+1).Trim()
        $values[$key] = $value
    }
    return $values
}

$repoRoot = Split-Path -Parent $PSScriptRoot
if (-not $EnvironmentFile) {
    $EnvironmentFile = Join-Path $repoRoot "config\environments\production.api.env"
}

$envValues = Read-DotEnv $EnvironmentFile

Write-Host ""
Write-Host "===================================================="
Write-Host "DYNETIC WMS PRODUCTION API CONFIG VALIDATION"
Write-Host "===================================================="
Write-Host "File .................. $EnvironmentFile"
Write-Host "Secrets ............... hidden"
Write-Host "===================================================="

if ($envValues["DB_NAME"] -ne "fulfilment_prod") {
    throw "Production DB_NAME must be fulfilment_prod."
}
Write-Host "[PASS] Production database target"

if ($envValues["AUTH_MODE"] -ne "OIDC") {
    throw "Production AUTH_MODE must be OIDC. DEV_HS256 is not permitted."
}
Write-Host "[PASS] Production auth mode"

foreach ($name in @("AUTH_PROVIDER_NAME","AUTH_ISSUER","AUTH_AUDIENCE","AUTH_JWKS_URL")) {
    if (-not $envValues[$name]) {
        throw "$name must be configured before production authentication is enabled."
    }
}
Write-Host "[PASS] OIDC configuration populated"

$orderSecret = $envValues["ORDER_ACCESS_TOKEN_SECRET"]
if (-not $orderSecret -or $orderSecret.Length -lt 32) {
    throw "ORDER_ACCESS_TOKEN_SECRET must be populated with at least 32 characters."
}
if ($orderSecret -match "change-me|test|local|example") {
    throw "ORDER_ACCESS_TOKEN_SECRET still looks like a development/example value."
}
Write-Host "[PASS] Guest access-token secret looks production-specific"

$origin = $envValues["STORE_FRONT_ORIGIN"]
if (-not $origin -or -not $origin.StartsWith("https://")) {
    throw "STORE_FRONT_ORIGIN must be an https:// production origin."
}
Write-Host "[PASS] HTTPS storefront origin"

if ($envValues["STRIPE_SECRET_KEY"]) {
    if ($envValues["STRIPE_SECRET_KEY"].StartsWith("sk_test_")) {
        throw "A Stripe TEST key is present in the production environment."
    }
    if (-not $envValues["STRIPE_SECRET_KEY"].StartsWith("sk_live_")) {
        throw "STRIPE_SECRET_KEY is populated but does not look like a Stripe live key."
    }
    Write-Host "[PASS] Stripe key is LIVE format"
} else {
    Write-Host "[INFO] Stripe live key is intentionally not configured yet"
}

if ($envValues["STRIPE_WEBHOOK_SECRET"]) {
    if (-not $envValues["STRIPE_WEBHOOK_SECRET"].StartsWith("whsec_")) {
        throw "STRIPE_WEBHOOK_SECRET is populated but is not a Stripe webhook secret."
    }
    Write-Host "[PASS] Stripe webhook secret format"
} else {
    Write-Host "[INFO] Stripe production webhook secret is intentionally not configured yet"
}

Write-Host ""
Write-Host "===================================================="
Write-Host "PRODUCTION API CONFIG VALIDATION PASSED"
Write-Host "===================================================="
