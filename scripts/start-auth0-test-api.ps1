param(
    [string]$EnvironmentFile = ""
)

$ErrorActionPreference = "Stop"

function Read-DotEnv([string]$Path) {
    $values = @{}
    if (-not (Test-Path $Path)) {
        throw "Environment file not found: $Path"
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
    $EnvironmentFile = Join-Path $repoRoot "config\environments\test.auth0.env"
}

$values = Read-DotEnv $EnvironmentFile

if ($values["DB_NAME"] -ne "fulfilment_test") {
    throw "Safety stop: Auth0 TEST runner must use fulfilment_test."
}
if ($values["AUTH_MODE"] -ne "OIDC") {
    throw "AUTH_MODE must be OIDC."
}
if ($values["AUTH_PROVIDER_NAME"] -ne "AUTH0") {
    throw "AUTH_PROVIDER_NAME must be AUTH0."
}
foreach ($required in @("AUTH_ISSUER","AUTH_AUDIENCE","AUTH_JWKS_URL")) {
    if (-not $values[$required]) {
        throw "$required is not configured."
    }
}

foreach ($entry in $values.GetEnumerator()) {
    [Environment]::SetEnvironmentVariable($entry.Key, $entry.Value, "Process")
}

Write-Host ""
Write-Host "===================================================="
Write-Host "STARTING DYNETIC WMS API - AUTH0 TEST"
Write-Host "===================================================="
Write-Host "Database .............. fulfilment_test"
Write-Host "Auth .................. OIDC / AUTH0"
Write-Host "apps\api\.env ......... NOT MODIFIED"
Write-Host "===================================================="
Write-Host ""

Push-Location (Join-Path $repoRoot "apps\api")
try {
    npm run dev
}
finally {
    Pop-Location
}
