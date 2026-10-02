param(
    [Parameter(Mandatory=$true)]
    [ValidateSet("VERIFY","TEST")]
    [string]$Target,

    [Parameter(Mandatory=$true)]
    [string]$Database,

    [string]$HostName = "localhost",
    [int]$Port = 5432,
    [string]$DbUser = "postgres",
    [string]$PsqlPath = "C:\Program Files\PostgreSQL\18\bin\psql.exe"
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

function Stop-Bootstrap([string]$Message) {
    Write-Host ""
    Write-Host "BOOTSTRAP BLOCKED: $Message" -ForegroundColor Red
    exit 1
}

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$manifestPath = Join-Path $repoRoot "database\bootstrap\fresh-install-manifest.txt"

if (-not (Test-Path $PsqlPath -PathType Leaf)) {
    Stop-Bootstrap "psql was not found at '$PsqlPath'."
}
if (-not (Test-Path $manifestPath -PathType Leaf)) {
    Stop-Bootstrap "Fresh-install manifest is missing."
}

if ($Target -eq "VERIFY" -and $Database -ne "fulfilment_bootstrap_verify") {
    Stop-Bootstrap "VERIFY may only target fulfilment_bootstrap_verify."
}

if ($Target -eq "TEST" -and $Database -ne "fulfilment_test") {
    Stop-Bootstrap "TEST may only target fulfilment_test."
}

$entries = @(
    Get-Content $manifestPath |
        ForEach-Object { $_.Trim() } |
        Where-Object { $_ -and -not $_.StartsWith("#") }
)

if ($entries.Count -eq 0) { Stop-Bootstrap "Fresh-install manifest is empty." }

$forbidden = '(^|[\\/])tests?([\\/]|$)|(^|[\\/])fixtures?([\\/]|$)|(^|[\\/])samples?([\\/]|$)|(^|[\\/])demo([\\/]|$)|(^|[\\/])load[-_]?tests?([\\/]|$)|smoke.*\.sql$|fixture.*\.sql$|load.*\.sql$'

$files = @()
foreach ($entry in $entries) {
    $n = $entry.Replace("/", "\")
    if ($n -match $forbidden) {
        Stop-Bootstrap "Forbidden test/fixture/demo/load path in manifest: $entry"
    }
    if ([IO.Path]::GetExtension($n).ToLowerInvariant() -ne ".sql") {
        Stop-Bootstrap "Only .sql files are permitted: $entry"
    }

    $full = Join-Path $repoRoot $n
    if (-not (Test-Path $full -PathType Leaf)) {
        Stop-Bootstrap "Manifest file does not exist: $entry"
    }

    if ($Target -eq "TEST" -and $Database -ne "fulfilment_test") {
    Stop-Bootstrap "TEST may only target fulfilment_test."
}
    $files += (Resolve-Path $full).Path
}

# Verify actual connected database.
$dbOut = & $PsqlPath -X -v ON_ERROR_STOP=1 -h $HostName -p $Port -U $DbUser -d $Database -Atc "select current_database();" 2>&1
if ($LASTEXITCODE -ne 0) {
    Stop-Bootstrap "Could not connect/verify target database: $($dbOut -join ' ')"
}
$actualDb = (($dbOut | Select-Object -Last 1).ToString()).Trim()
if ($actualDb -ne $Database) {
    Stop-Bootstrap "Connected database '$actualDb' does not match '$Database'."
}

# Fresh-install guard: no user tables and no application schemas may already exist.
$objectCount = & $PsqlPath -X -v ON_ERROR_STOP=1 -h $HostName -p $Port -U $DbUser -d $Database -Atc @"
SELECT
  (SELECT count(*) FROM information_schema.tables
    WHERE table_schema NOT IN ('pg_catalog','information_schema')) +
  (SELECT count(*) FROM information_schema.schemata
    WHERE schema_name IN ('api','audit','config','core','interface'));
"@
if ($LASTEXITCODE -ne 0) { Stop-Bootstrap "Could not verify database emptiness." }

if ([int](($objectCount | Select-Object -Last 1).ToString().Trim()) -ne 0) {
    Stop-Bootstrap "Database is not empty. Fresh bootstrap is forbidden."
}

Write-Host ""
Write-Host "DYNETIC FRESH DATABASE BOOTSTRAP" -ForegroundColor Cyan
Write-Host "Target   : $Target"
Write-Host "Database : $Database"
Write-Host "Files    : $($files.Count)"
Write-Host ""

foreach ($sql in $files) {
    $relative = $sql.Substring($repoRoot.Length).TrimStart("\")
    Write-Host "Applying: $relative"
    # PostgreSQL NOTICE/WARNING messages are written to stderr.
    # Windows PowerShell must not convert those into terminating errors;
    # the authoritative failure signal remains the psql exit code with
    # ON_ERROR_STOP=1 enabled.
    $previousErrorActionPreference = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'

    try {
        $psqlOutput = & $PsqlPath -X -q -P pager=off -v ON_ERROR_STOP=1 -h $HostName -p $Port -U $DbUser -d $Database -o NUL -f $sql 2>&1
        $psqlExitCode = $LASTEXITCODE
    }
    finally {
        $ErrorActionPreference = $previousErrorActionPreference
    }

    if ($psqlOutput) {
        $psqlOutput | ForEach-Object { Write-Host $_ }
    }

    if ($psqlExitCode -ne 0) {
        Stop-Bootstrap "psql failed on '$relative' with exit code $psqlExitCode."
    }
}

Write-Host ""
Write-Host "BOOTSTRAP COMPLETE" -ForegroundColor Green
