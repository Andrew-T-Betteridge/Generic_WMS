param(
    [string]$DatabaseName = "fulfilment_prod",
    [string]$OutputDirectory = ""
)

$ErrorActionPreference = "Stop"

function Read-DotEnv([string]$Path) {
    $values = @{}
    if (-not (Test-Path $Path)) { return $values }
    foreach ($line in Get-Content $Path) {
        $trimmed = $line.Trim()
        if (-not $trimmed -or $trimmed.StartsWith("#")) { continue }
        $eq = $trimmed.IndexOf("=")
        if ($eq -lt 1) { continue }
        $values[$trimmed.Substring(0,$eq).Trim()] = $trimmed.Substring($eq+1).Trim()
    }
    return $values
}

if ($DatabaseName -ne "fulfilment_prod") {
    throw "Safety stop: production backup script only permits fulfilment_prod."
}

$repoRoot = Split-Path -Parent $PSScriptRoot
$apiEnv = Read-DotEnv (Join-Path $repoRoot "apps\api\.env")
$prodEnvPath = Join-Path $repoRoot "config\environments\production.api.env"
$prodEnv = Read-DotEnv $prodEnvPath

$dbHost = if ($prodEnv["DB_HOST"]) { $prodEnv["DB_HOST"] } elseif ($apiEnv["DB_HOST"]) { $apiEnv["DB_HOST"] } else { "localhost" }
$dbPort = if ($prodEnv["DB_PORT"]) { $prodEnv["DB_PORT"] } elseif ($apiEnv["DB_PORT"]) { $apiEnv["DB_PORT"] } else { "5432" }
$dbUser = if ($prodEnv["DB_USER"]) { $prodEnv["DB_USER"] } elseif ($apiEnv["DB_USER"]) { $apiEnv["DB_USER"] } else { "postgres" }

$pgDump = "C:\Program Files\PostgreSQL\18\bin\pg_dump.exe"
if (-not (Test-Path $pgDump)) {
    throw "pg_dump not found at $pgDump"
}

if (-not $OutputDirectory) {
    $OutputDirectory = Join-Path $repoRoot "backups"
}
New-Item -ItemType Directory -Force -Path $OutputDirectory | Out-Null

$timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
$output = Join-Path $OutputDirectory "fulfilment_prod-$timestamp.backup"

Write-Host ""
Write-Host "Creating DYNETIC WMS production backup..."
Write-Host "Database .............. fulfilment_prod"
Write-Host "Output ................ $output"

& $pgDump `
    -h $dbHost `
    -p $dbPort `
    -U $dbUser `
    -d $DatabaseName `
    -F c `
    -f $output

if ($LASTEXITCODE -ne 0) {
    throw "Production pg_dump failed."
}

if (-not (Test-Path $output) -or (Get-Item $output).Length -le 0) {
    throw "Backup file was not created correctly."
}

$sizeMb = [Math]::Round((Get-Item $output).Length / 1MB, 2)
Write-Host "[PASS] Production backup created ($sizeMb MB)"
Write-Host ""
Write-Host "IMPORTANT: backups\ should not be committed to Git."
