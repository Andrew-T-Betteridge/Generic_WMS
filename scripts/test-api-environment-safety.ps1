$ErrorActionPreference="Stop"

$repoRoot=Split-Path $PSScriptRoot -Parent
$apiPath=Join-Path $repoRoot "apps\api"

$environmentNames=@(
    "DYNETIC_ENVIRONMENT",
    "PORT",
    "DEFAULT_CLIENT_ID",
    "STORE_FRONT_ORIGIN",
    "ADMIN_ORIGIN",
    "DB_HOST",
    "DB_PORT",
    "DB_NAME",
    "DB_USER",
    "DB_PASSWORD",
    "STRIPE_MODE",
    "STRIPE_SECRET_KEY",
    "AUTH_MODE",
    "AUTH_PROVIDER_NAME",
    "AUTH_ISSUER",
    "AUTH_AUDIENCE",
    "AUTH_JWKS_URL",
    "AUTH_DEV_HS256_SECRET",
    "DOTENV_CONFIG_PATH"
)

$saved=@{}

foreach($name in $environmentNames){
    $item=Get-Item "Env:$name" -ErrorAction SilentlyContinue

    if($null -ne $item){
        $saved[$name]=@{
            Exists=$true
            Value=$item.Value
        }
    }
    else {
        $saved[$name]=@{
            Exists=$false
            Value=$null
        }
    }
}

function Set-ProbeEnvironment {
    param(
        [hashtable]$Values
    )

    foreach($name in $environmentNames){
        Remove-Item "Env:$name" -ErrorAction SilentlyContinue
    }

    foreach($entry in $Values.GetEnumerator()){
        Set-Item "Env:$($entry.Key)" $entry.Value
    }
}

function New-TestEnvironment {
    return @{
        DYNETIC_ENVIRONMENT="TEST"
        PORT="3101"
        DEFAULT_CLIENT_ID="FINATICS"
        STORE_FRONT_ORIGIN="http://localhost:5173"
        DB_HOST="localhost"
        DB_PORT="5432"
        DB_NAME="fulfilment_test"
        DB_USER="postgres"
        DB_PASSWORD="environment-safety-test"
        STRIPE_MODE="TEST"
        STRIPE_SECRET_KEY="sk_test_environment_safety"
        AUTH_MODE="OIDC"
        AUTH_PROVIDER_NAME="AUTH0"
        AUTH_ISSUER="https://environment-safety.auth0.com/"
        AUTH_AUDIENCE="https://test-api.finaticsaquatics.co.uk"
        AUTH_JWKS_URL="https://environment-safety.auth0.com/.well-known/jwks.json"
    }
}

function New-ProductionEnvironment {
    return @{
        DYNETIC_ENVIRONMENT="PRODUCTION"
        PORT="3001"
        DEFAULT_CLIENT_ID="FINATICS"
        STORE_FRONT_ORIGIN="https://www.finaticsaquatics.co.uk"
        DB_HOST="localhost"
        DB_PORT="5432"
        DB_NAME="fulfilment_prod"
        DB_USER="postgres"
        DB_PASSWORD="environment-safety-test"
        STRIPE_MODE="TEST"
        STRIPE_SECRET_KEY="sk_test_environment_safety"
        AUTH_MODE="OIDC"
        AUTH_PROVIDER_NAME="AUTH0"
        AUTH_ISSUER="https://environment-safety.auth0.com/"
        AUTH_AUDIENCE="https://api.finaticsaquatics.co.uk"
        AUTH_JWKS_URL="https://environment-safety.auth0.com/.well-known/jwks.json"
    }
}

function Invoke-Probe {
    param(
        [string]$Name,
        [hashtable]$Values,
        [bool]$ShouldPass,
        [string]$ExpectedFailure=""
    )

    Set-ProbeEnvironment $Values

    Push-Location $apiPath

    try {
        $output=& npx.cmd tsx -e "import('./src/env.ts').then(function(){console.log('ENV_OK')}).catch(function(e){console.log(e.message);process.exit(42)})" | Out-String
            Out-String

        $exitCode=$LASTEXITCODE
    }
    finally {
        Pop-Location
    }

    if($ShouldPass){
        if($exitCode -ne 0 -or $output -notmatch "ENV_OK"){
            throw "$Name failed unexpectedly.`n$output"
        }

        Write-Host "[PASS] $Name"
        return
    }

    if($exitCode -eq 0){
        throw "$Name was accepted unexpectedly."
    }

    if(
        $ExpectedFailure -and
        $output -notmatch [regex]::Escape($ExpectedFailure)
    ){
        throw "$Name failed for the wrong reason.`n$output"
    }

    Write-Host "[PASS] $Name rejected"
}

try {
    Write-Host "===================================================="
    Write-Host "DYNETIC WMS API ENVIRONMENT SAFETY REGRESSION"
    Write-Host "===================================================="

    $case=New-TestEnvironment
    Invoke-Probe "Valid TEST configuration" $case $true

    $case=New-TestEnvironment
    $case.DB_NAME="fulfilment_prod"
    Invoke-Probe `
        "TEST using production database" `
        $case `
        $false `
        "TEST must use DB_NAME=fulfilment_test"

    $case=New-TestEnvironment
    $case.PORT="3001"
    Invoke-Probe `
        "TEST using production API port" `
        $case `
        $false `
        "TEST must use PORT=3101"

    $case=New-TestEnvironment
    $case.DB_HOST="production-db.example.com"
    Invoke-Probe `
        "TEST using non-local database host" `
        $case `
        $false `
        "TEST must use DB_HOST=localhost"

    $case=New-TestEnvironment
    $case.AUTH_MODE="DEV_HS256"
    $case.AUTH_DEV_HS256_SECRET="temporary-environment-safety-value"
    Invoke-Probe `
        "TEST using DEV_HS256" `
        $case `
        $false `
        "TEST must use AUTH_MODE=OIDC"

    $case=New-TestEnvironment
    $case.STRIPE_SECRET_KEY="sk_live_environment_safety_fake"
    Invoke-Probe `
        "TEST using live Stripe key" `
        $case `
        $false `
        "STRIPE_MODE=TEST cannot use a live Stripe secret key"

    $case=New-ProductionEnvironment
    Invoke-Probe "Valid PRODUCTION contract" $case $true

    $case=New-ProductionEnvironment
    $case.DB_NAME="fulfilment_test"
    Invoke-Probe `
        "PRODUCTION using TEST database" `
        $case `
        $false `
        "PRODUCTION must use DB_NAME=fulfilment_prod"

    $case=New-ProductionEnvironment
    $case.AUTH_AUDIENCE="https://test-api.finaticsaquatics.co.uk"
    Invoke-Probe `
        "PRODUCTION using TEST Auth0 audience" `
        $case `
        $false `
        "PRODUCTION must use AUTH_AUDIENCE=https://api.finaticsaquatics.co.uk"

    $case=New-ProductionEnvironment
    $case.AUTH_MODE="DEV_HS256"
    $case.AUTH_DEV_HS256_SECRET="temporary-environment-safety-value"
    Invoke-Probe `
        "PRODUCTION using DEV_HS256" `
        $case `
        $false `
        "PRODUCTION must use AUTH_MODE=OIDC"

    Write-Host ""
    Write-Host "DYNETIC WMS API ENVIRONMENT SAFETY PASSED: 10/10"
}
finally {
    foreach($name in $environmentNames){
        Remove-Item "Env:$name" -ErrorAction SilentlyContinue

        if($saved[$name].Exists){
            Set-Item "Env:$name" $saved[$name].Value
        }
    }
}
