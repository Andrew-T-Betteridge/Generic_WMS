param(
    [string]$Database = "fulfilment_test",
    [string]$DbUser = "postgres",
    [int]$Port = 3101
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

if ($Database -ne "fulfilment_test") {
    throw "SAFETY STOP: runtime API startup smoke may only use fulfilment_test."
}

$root = (Resolve-Path "$PSScriptRoot\..").Path
$api = Join-Path $root "apps\api"

Write-Host ""
Write-Host "=== STATIC FASTIFY ROUTE COLLISION CHECK: ALL API TS FILES ==="

$routes = @()

Get-ChildItem `
    -Path (Join-Path $api "src") `
    -Filter "*.ts" `
    -File `
    -Recurse |
ForEach-Object {
    $file = $_
    $content = Get-Content $file.FullName -Raw

    foreach ($m in [regex]::Matches(
        $content,
        'app\.(get|post|patch|put|delete)\("([^"]+)"'
    )) {
        $routes += [pscustomobject]@{
            Method = $m.Groups[1].Value.ToUpperInvariant()
            Path   = $m.Groups[2].Value
            File   = $file.FullName.Substring($root.Length + 1)
        }
    }
}

$duplicates = @(
    $routes |
    Group-Object Method,Path |
    Where-Object { $_.Count -gt 1 }
)

if ($duplicates.Count -gt 0) {
    foreach ($dup in $duplicates) {
        Write-Host "DUPLICATE ROUTE: $($dup.Name)"
        $dup.Group | Format-Table -AutoSize
    }
    throw "Duplicate static Fastify method+path registrations remain."
}

$audit = @($routes | Where-Object {
    $_.Method -eq "GET" -and $_.Path -eq "/api/admin/audit"
})

if ($audit.Count -ne 1) {
    throw "Expected one canonical GET /api/admin/audit; found $($audit.Count)."
}

if ($audit[0].File -notlike "*admin-operations.ts") {
    throw "Canonical GET /api/admin/audit is not owned by admin-operations.ts."
}

Write-Host "STATIC ROUTE CONTRACT PASS: $($routes.Count) route registrations; no duplicate method+path pairs."

$existing = Get-NetTCPConnection `
    -State Listen `
    -LocalPort $Port `
    -ErrorAction SilentlyContinue

if ($existing) {
    throw "Port $Port is already in use."
}

if ($Port -ne 3101) {
    throw "TEST runtime startup smoke must use safety-approved PORT=3101."
}

if ($Database -ne "fulfilment_test") {
    throw "TEST runtime startup smoke must use DB_NAME=fulfilment_test."
}

$stamp = Get-Date -Format "yyyyMMdd-HHmmss"
$launcher = Join-Path $env:TEMP "dynetic-api-startup-$stamp.ps1"
$stdout = Join-Path $env:TEMP "dynetic-api-startup-$stamp.stdout.log"
$stderr = Join-Path $env:TEMP "dynetic-api-startup-$stamp.stderr.log"

$launcherBody = @"
`$ErrorActionPreference='Continue'
`$env:DYNETIC_ENVIRONMENT='TEST'
`$env:PORT='$Port'
`$env:DB_HOST='localhost'
`$env:DB_PORT='5432'
`$env:DB_NAME='$Database'
`$env:DB_USER='$DbUser'
`$env:STRIPE_MODE='TEST'
`$env:AUTH_MODE='OIDC'
`$env:AUTH_PROVIDER_NAME='AUTH0'
`$env:AUTH_ISSUER='https://example.auth0.com/'
`$env:AUTH_AUDIENCE='https://test-api.finaticsaquatics.co.uk'
`$env:AUTH_JWKS_URL='https://example.auth0.com/.well-known/jwks.json'
`$env:ADMIN_ROLE='admin'
`$env:DEFAULT_CLIENT_ID='FINATICS'
`$env:STORE_FRONT_ORIGIN='http://localhost:5173'
`$env:ORDER_ACCESS_TOKEN_SECRET='dynetic-local-startup-smoke-order-token'
`$env:PAYMENT_TIMEOUT_MINUTES='30'
Set-Location '$api'
npm start
exit `$LASTEXITCODE
"@

[IO.File]::WriteAllText(
    $launcher,
    $launcherBody,
    [Text.UTF8Encoding]::new($false)
)

Write-Host ""
Write-Host "=== REAL API PROCESS STARTUP CHECK ==="

$process = Start-Process `
    -FilePath "powershell.exe" `
    -ArgumentList @(
        "-NoProfile",
        "-ExecutionPolicy","Bypass",
        "-File",$launcher
    ) `
    -PassThru `
    -RedirectStandardOutput $stdout `
    -RedirectStandardError $stderr

try {
    $health = $null

    for ($i=0; $i -lt 40; $i++) {
        Start-Sleep -Milliseconds 500
        $process.Refresh()

        if ($process.HasExited) {
            break
        }

        try {
            $health = Invoke-RestMethod `
                -Uri "http://127.0.0.1:$Port/health" `
                -Method Get `
                -TimeoutSec 2

            if ($health.ok -eq $true) {
                break
            }
        }
        catch {}
    }

    if (-not $health) {
        Write-Host "--- API STDOUT ---"
        if (Test-Path $stdout) { Get-Content $stdout }
        Write-Host "--- API STDERR ---"
        if (Test-Path $stderr) { Get-Content $stderr }

        if ($process.HasExited) {
            throw "API process exited before /health became available. Exit=$($process.ExitCode)"
        }

        throw "API /health did not become available."
    }

    if ([string]$health.version -ne "0.3.15") {
        throw "Expected version 0.3.15 from TEST health; got '$($health.version)'."
    }

    if ([string]$health.environment -ne "TEST") {
        throw "Expected environment TEST; got '$($health.environment)'."
    }

    $status = $null
    try {
        $response = Invoke-WebRequest `
            -UseBasicParsing `
            -Uri "http://127.0.0.1:$Port/api/admin/audit" `
            -TimeoutSec 3
        $status = [int]$response.StatusCode
    }
    catch {
        if ($_.Exception.Response) {
            $status = [int]$_.Exception.Response.StatusCode
        }
        else {
            throw
        }
    }

    if ($status -ne 401) {
        throw "Unauthenticated canonical admin audit route returned HTTP $status; expected exactly 401."
    }

    Write-Host "API STARTUP PASS: Fastify started, TEST health=0.3.15, unauthenticated admin guard HTTP=401."
}
finally {
    if ($process -and -not $process.HasExited) {
        & taskkill.exe /PID $process.Id /T /F *> $null
    }

    Remove-Item $launcher -Force -ErrorAction SilentlyContinue
}
