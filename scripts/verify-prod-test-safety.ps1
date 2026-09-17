param(
    [string]$RepoRoot = (Get-Location).Path
)

$ErrorActionPreference = "Stop"
$RepoRoot = (Resolve-Path $RepoRoot).Path

$serverPath = Join-Path $RepoRoot "apps\api\src\server.ts"
$dbTestsPath = Join-Path $RepoRoot "database\tests"
$scriptsPath = Join-Path $RepoRoot "scripts"
$helperPath = Join-Path $scriptsPath "Test-Safety.ps1"

$failures = New-Object System.Collections.Generic.List[string]

Write-Host ""
Write-Host "DYNETIC PROD TEST-SAFETY VERIFICATION V2" -ForegroundColor Cyan
Write-Host ""

# API environment must come from the actual PostgreSQL connection.
if (-not (Test-Path $serverPath)) {
    $failures.Add("apps/api/src/server.ts is missing.")
}
else {
    $server = Get-Content $serverPath -Raw
    if ($server -notmatch 'current_database\(\) as database_name') {
        $failures.Add("API /health is not deriving environment from current_database().")
    }
    if ($server -notmatch 'fulfilment_prod') {
        $failures.Add("API /health does not map fulfilment_prod.")
    }
    if ($server -notmatch '"PROD"') {
        $failures.Add("API /health does not expose PROD environment mapping.")
    }
    if ($server -notmatch 'environment') {
        $failures.Add("API /health does not return environment.")
    }
}

# Every database test must self-guard before its test body.
$sqlFiles = @(Get-ChildItem $dbTestsPath -File -Filter "*.sql")
if ($sqlFiles.Count -eq 0) {
    $failures.Add("No database test SQL files were found.")
}

foreach ($file in $sqlFiles) {
    $content = Get-Content $file.FullName -Raw
    if ($content -notmatch 'DYNETIC_TEST_ENVIRONMENT_GUARD_BEGIN') {
        $failures.Add("UNGUARDED SQL TEST: database/tests/$($file.Name)")
    }
    if ($content -notmatch 'fulfilment_dev' -or $content -notmatch 'fulfilment_test') {
        $failures.Add("SQL TEST DOES NOT CONTAIN DEV/TEST ALLOWLIST: database/tests/$($file.Name)")
    }
}

# Shared helper must provide all three protections.
if (-not (Test-Path $helperPath)) {
    $failures.Add("scripts/Test-Safety.ps1 is missing.")
}
else {
    $helper = Get-Content $helperPath -Raw
    foreach ($fn in @(
        'Assert-DyneticNonProductionDatabaseName',
        'Assert-DyneticNonProductionApi',
        'Assert-DyneticTestScriptSafety'
    )) {
        if ($helper -notmatch [regex]::Escape($fn)) {
            $failures.Add("scripts/Test-Safety.ps1 is missing $fn.")
        }
    }
}

# NO REVIEW STATE EXISTS IN V2.
# Every test PowerShell script must either be permanently disabled (test-prod-smoke)
# or contain the universal wrapper guard.
$psTests = @(Get-ChildItem $scriptsPath -File -Filter "test-*.ps1")
foreach ($file in $psTests) {
    if ($file.Name -ieq "Test-Safety.ps1") { continue }

    $content = Get-Content $file.FullName -Raw

    if ($file.Name -ieq "test-prod-smoke.ps1") {
        if ($content -notmatch 'SAFETY STOP - PROD TEST EXECUTION IS DISABLED') {
            $failures.Add("PROD SMOKE TEST IS NOT PERMANENTLY DISABLED: scripts/$($file.Name)")
        }
        if (
            $content -match '(?i)\bInvoke-Psql\b' -or
            $content -match '(?i)\bpsql(?:\.exe)?\b' -or
            $content -match '(?i)\bInvoke-RestMethod\b' -or
            $content -match '(?i)\bInvoke-WebRequest\b'
        ) {
            $failures.Add("DISABLED PROD SMOKE FILE STILL CONTAINS DB/API EXECUTION CODE: scripts/$($file.Name)")
        }
        continue
    }

    if ($content -notmatch 'DYNETIC_TEST_WRAPPER_GUARD_BEGIN') {
        $failures.Add("UNGUARDED POWERSHELL TEST WRAPPER: scripts/$($file.Name)")
        continue
    }

    if ($content -notmatch 'Assert-DyneticTestScriptSafety') {
        $failures.Add("UNIVERSAL SAFETY CALL MISSING: scripts/$($file.Name)")
    }

    $usesApi = (
        $content -match '(?i)\bBaseUrl\b' -or
        $content -match '(?i)\bInvoke-RestMethod\b' -or
        $content -match '(?i)\bInvoke-WebRequest\b' -or
        $content -match '(?i)localhost:3001' -or
        $content -match '(?i)/api/'
    )

    if ($usesApi -and $content -notmatch 'Assert-DyneticNonProductionApi') {
        $failures.Add("API TEST WITHOUT API ENVIRONMENT GUARD: scripts/$($file.Name)")
    }
}

# Node API/load tests must have their own environment guard.
$mjsTests = @(Get-ChildItem $scriptsPath -File -Filter "test-*.mjs")
foreach ($file in $mjsTests) {
    $content = Get-Content $file.FullName -Raw
    $usesApi = ($content -match 'fetch\(' -or $content -match '/health')
    if ($usesApi -and $content -notmatch 'DYNETIC_TEST_API_ENVIRONMENT_GUARD') {
        $failures.Add("UNGUARDED NODE API TEST: scripts/$($file.Name)")
    }
}

if ($failures.Count -gt 0) {
    Write-Host "FAIL - PROD TEST SAFETY IS NOT COMPLETE" -ForegroundColor Red
    Write-Host ""
    foreach ($failure in $failures) {
        Write-Host " - $failure" -ForegroundColor Red
    }
    Write-Host ""
    Write-Host "There is deliberately no REVIEW/pass-through state. Any ambiguity is a failure." -ForegroundColor Yellow
    exit 1
}

Write-Host "PASS - FAIL-CLOSED TEST SAFETY IS COMPLETE" -ForegroundColor Green
Write-Host ""
Write-Host "Database SQL tests ...... only fulfilment_dev / fulfilment_test"
Write-Host "PowerShell test wrappers  universal preflight required"
Write-Host "HTTP/API tests .......... API must report DEV or TEST"
Write-Host "Node/load tests ......... API must report DEV or TEST"
Write-Host "test-prod-* ............. hard-stop before DB/API execution"
Write-Host "Unknown target .......... hard-stop"
Write-Host "PROD .................... hard-stop"
exit 0
