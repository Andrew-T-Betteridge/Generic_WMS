param(
    [string]$EnvironmentFile = "",
    [switch]$ValidateOnly
)

$ErrorActionPreference = "Stop"

function Read-DotEnv([string]$Path) {
    $values = @{}

    if (-not (Test-Path $Path)) {
        throw "Environment file not found: $Path"
    }

    foreach ($line in Get-Content $Path) {
        $trimmed = $line.Trim()

        if (-not $trimmed -or $trimmed.StartsWith("#")) {
            continue
        }

        $eq = $trimmed.IndexOf("=")

        if ($eq -lt 1) {
            continue
        }

        $key = $trimmed.Substring(0,$eq).Trim()
        $value = $trimmed.Substring($eq+1).Trim()

        $values[$key] = $value
    }

    return $values
}

function Assert-ExactValue {
    param(
        [hashtable]$Values,
        [string]$Key,
        [string]$Expected
    )

    $actual = [string]$Values[$Key]

    if($actual -cne $Expected){
        throw "TEST API safety stop: $Key must be '$Expected', not '$actual'."
    }
}

function Assert-RequiredValue {
    param(
        [hashtable]$Values,
        [string]$Key
    )

    if([string]::IsNullOrWhiteSpace([string]$Values[$Key])){
        throw "TEST API safety stop: $Key is not configured."
    }
}

$repoRoot = Split-Path -Parent $PSScriptRoot

if (-not $EnvironmentFile) {
    $EnvironmentFile = Join-Path `
        $repoRoot `
        "config\environments\test.auth0.env"
}

$EnvironmentFile = (Resolve-Path $EnvironmentFile).Path
$values = Read-DotEnv $EnvironmentFile

Assert-ExactValue $values "DYNETIC_ENVIRONMENT" "TEST"
Assert-ExactValue $values "DB_HOST" "localhost"
Assert-ExactValue $values "DB_PORT" "5432"
Assert-ExactValue $values "DB_NAME" "fulfilment_test"
Assert-ExactValue $values "PORT" "3101"
Assert-ExactValue $values "STRIPE_MODE" "TEST"
Assert-ExactValue $values "AUTH_MODE" "OIDC"
Assert-ExactValue $values "AUTH_PROVIDER_NAME" "AUTH0"
Assert-ExactValue `
    $values `
    "AUTH_AUDIENCE" `
    "https://test-api.finaticsaquatics.co.uk"

foreach($required in @(
    "DB_USER",
    "AUTH_ISSUER",
    "AUTH_JWKS_URL"
)){
    Assert-RequiredValue $values $required
}

try {
    $issuer = [uri]$values["AUTH_ISSUER"]
    $jwks = [uri]$values["AUTH_JWKS_URL"]
}
catch {
    throw "TEST API safety stop: Auth0 issuer/JWKS configuration is not a valid URL."
}

if($issuer.Scheme -ne "https"){
    throw "TEST API safety stop: AUTH_ISSUER must use HTTPS."
}

if($jwks.Scheme -ne "https"){
    throw "TEST API safety stop: AUTH_JWKS_URL must use HTTPS."
}

if($issuer.Host -ne $jwks.Host){
    throw "TEST API safety stop: Auth0 issuer and JWKS hosts do not match."
}

# Prevent inherited shell values or apps/api/.env from becoming TEST configuration.
$apiEnvironmentKeys=@(
    "PORT",
    "DEFAULT_CLIENT_ID",
    "STORE_FRONT_ORIGIN",
    "ADMIN_ORIGIN",
    "DB_HOST",
    "DB_PORT",
    "DB_NAME",
    "DB_USER",
    "DB_PASSWORD",
    "AUTH_MODE",
    "AUTH_PROVIDER_NAME",
    "AUTH_ISSUER",
    "AUTH_AUDIENCE",
    "AUTH_JWKS_URL",
    "ADMIN_ROLE",
    "AUTH_DEV_HS256_SECRET",
    "ORDER_ACCESS_TOKEN_SECRET",
    "ORDER_ACCESS_TOKEN_TTL",
    "PAYMENT_TIMEOUT_MINUTES",
    "STRIPE_MODE",
    "STRIPE_SECRET_KEY",
    "STRIPE_WEBHOOK_SECRET",
    "STRIPE_WEBHOOK_TOLERANCE_SECONDS",
    "ADDRESS_LOOKUP_PROVIDER",
    "ADDRESS_LOOKUP_API_KEY",
    "ADDRESS_LOOKUP_TIMEOUT_MS",
    "DYNETIC_ENVIRONMENT",
    "DOTENV_CONFIG_PATH"
)

foreach($key in $apiEnvironmentKeys){
    [Environment]::SetEnvironmentVariable(
        $key,
        $null,
        "Process"
    )
}

foreach($entry in $values.GetEnumerator()){
    [Environment]::SetEnvironmentVariable(
        $entry.Key,
        $entry.Value,
        "Process"
    )
}

# dotenv/config must read TEST configuration, never apps/api/.env.
[Environment]::SetEnvironmentVariable(
    "DOTENV_CONFIG_PATH",
    $EnvironmentFile,
    "Process"
)

Write-Host ""
Write-Host "===================================================="
Write-Host "DYNETIC WMS API - ISOLATED TEST"
Write-Host "===================================================="
Write-Host "Environment ........... TEST"
Write-Host "Database host ......... localhost:5432"
Write-Host "Database .............. fulfilment_test"
Write-Host "API ................... http://localhost:3101"
Write-Host "Stripe mode ........... TEST"
Write-Host "Auth .................. OIDC / AUTH0"
Write-Host "Auth audience ......... https://test-api.finaticsaquatics.co.uk"
Write-Host "dotenv source ......... TEST environment file"
Write-Host "apps\api\.env ......... NOT USED"
Write-Host "===================================================="
Write-Host ""

if($ValidateOnly){
    Write-Host "PASS - TEST API CONFIGURATION IS FAIL-CLOSED"
    return
}

Push-Location (Join-Path $repoRoot "apps\api")

try {
    npm run dev

    if($LASTEXITCODE -ne 0){
        throw "TEST API exited with code $LASTEXITCODE."
    }
}
finally {
    Pop-Location
}
