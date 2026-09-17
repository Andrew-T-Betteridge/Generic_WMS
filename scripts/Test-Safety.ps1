# DYNETIC WMS test-safety helpers.
# Tests are allowed only against DEV or TEST.
# PROD and unknown/unverifiable targets fail closed.

function Assert-DyneticNonProductionDatabaseName {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$DatabaseName
    )

    $db = $DatabaseName.Trim().ToLowerInvariant()

    if ($db -eq "fulfilment_prod" -or $db -eq "prod" -or $db -eq "production") {
        throw "SAFETY STOP: tests are FORBIDDEN against PROD database '$DatabaseName'. No test has been run."
    }

    if ($db -notin @("fulfilment_dev", "fulfilment_test")) {
        throw "SAFETY STOP: database '$DatabaseName' is not an approved test database. Only fulfilment_dev or fulfilment_test are allowed."
    }

    Write-Host "[SAFETY] Database verified as $db." -ForegroundColor Green
    return $db
}

function Assert-DyneticNonProductionApi {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$BaseUrl
    )

    $base = $BaseUrl.TrimEnd('/')

    try {
        $health = Invoke-RestMethod -Method Get -Uri "$base/health"
    }
    catch {
        throw "SAFETY STOP: could not verify the DYNETIC API environment from $base/health. No test has been run. $($_.Exception.Message)"
    }

    $environment = [string]$health.environment
    if ([string]::IsNullOrWhiteSpace($environment)) {
        throw "SAFETY STOP: API /health did not return an environment. No test has been run."
    }

    $environment = $environment.Trim().ToUpperInvariant()

    if ($environment -eq "PROD") {
        throw "SAFETY STOP: tests are FORBIDDEN against the PROD API. No test has been run."
    }

    if ($environment -notin @("DEV", "TEST")) {
        throw "SAFETY STOP: API environment '$environment' is not an approved test environment. Only DEV or TEST are allowed."
    }

    Write-Host "[SAFETY] API environment verified as $environment." -ForegroundColor Green
    return $environment
}

function Assert-DyneticTestScriptSafety {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$ScriptPath,

        [Parameter(Mandatory = $false)]
        [System.Collections.IDictionary]$BoundParameters
    )

    $resolved = (Resolve-Path $ScriptPath).Path
    $name = [System.IO.Path]::GetFileName($resolved)

    # Any test-prod-* script is intentionally unusable. This happens before
    # a DB connection or API request can be opened.
    if ($name -like "test-prod-*") {
        throw "SAFETY STOP: '$name' is disabled by policy. No test may run against PROD."
    }

    if ($null -eq $BoundParameters) {
        $BoundParameters = @{}
    }

    # Reject any explicit PROD-looking value supplied to a test wrapper.
    foreach ($entry in $BoundParameters.GetEnumerator()) {
        if ($null -eq $entry.Value) { continue }

        $value = [string]$entry.Value
        $normal = $value.Trim().ToLowerInvariant()

        if (
            $normal -eq "prod" -or
            $normal -eq "production" -or
            $normal -eq "fulfilment_prod" -or
            $normal -match '(^|[^a-z0-9_])fulfilment_prod([^a-z0-9_]|$)'
        ) {
            throw "SAFETY STOP: parameter '$($entry.Key)' targets PROD ('$value'). No test has been run."
        }
    }

    # If DB_NAME is in the process environment it must be explicitly DEV/TEST.
    if (-not [string]::IsNullOrWhiteSpace($env:DB_NAME)) {
        $null = Assert-DyneticNonProductionDatabaseName -DatabaseName $env:DB_NAME
    }

    $source = Get-Content $resolved -Raw

    # Explicit executable-looking PROD database targets are forbidden.
    $prodTargetPatterns = @(
        '(?i)-d\s+["'']?fulfilment_prod\b',
        '(?i)\bDB_NAME\s*=\s*["'']fulfilment_prod["'']',
        '(?i)\bDatabaseName\s*=\s*["'']fulfilment_prod["'']',
        '(?i)\bDbName\s*=\s*["'']fulfilment_prod["'']',
        '(?i)Invoke-Psql[^\r\n]*fulfilment_prod'
    )
    foreach ($pattern in $prodTargetPatterns) {
        if ($source -match $pattern) {
            throw "SAFETY STOP: '$name' contains an executable PROD database target. No test has been run."
        }
    }

    $usesDatabase = (
        $source -match '(?i)\bpsql(?:\.exe)?\b' -or
        $source -match '(?i)\bInvoke-Psql\b' -or
        $source -match '(?i)\bNpgsql\b'
    )

    if ($usesDatabase) {
        # Explicit database parameters supplied by the caller take precedence.
        $dbParameterFound = $false
        foreach ($entry in $BoundParameters.GetEnumerator()) {
            if ([string]$entry.Key -match '(?i)^(database|databasename|dbname|db)$') {
                $dbParameterFound = $true
                $null = Assert-DyneticNonProductionDatabaseName -DatabaseName ([string]$entry.Value)
            }
        }

        if (-not $dbParameterFound -and [string]::IsNullOrWhiteSpace($env:DB_NAME)) {
            # Default/hard-coded DB target must be visibly DEV or TEST.
            $hasApprovedDatabaseLiteral = (
                $source -match '(?i)\bfulfilment_dev\b' -or
                $source -match '(?i)\bfulfilment_test\b'
            )

            if (-not $hasApprovedDatabaseLiteral) {
                throw "SAFETY STOP: '$name' uses PostgreSQL but its database target cannot be proven to be DEV or TEST."
            }
        }
    }

    $usesApi = (
        $source -match '(?i)\bBaseUrl\b' -or
        $source -match '(?i)\bInvoke-RestMethod\b' -or
        $source -match '(?i)\bInvoke-WebRequest\b' -or
        $source -match '(?i)localhost:3001' -or
        $source -match '(?i)/api/'
    )

    if ($usesApi -and $source -notmatch '\bAssert-DyneticNonProductionApi\b') {
        throw "SAFETY STOP: '$name' accesses an API but has no API environment guard."
    }

    Write-Host "[SAFETY] Test wrapper preflight passed: $name" -ForegroundColor Green
}
