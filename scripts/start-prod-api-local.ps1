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
        $values[$trimmed.Substring(0,$eq).Trim()] = $trimmed.Substring($eq+1).Trim()
    }
    return $values
}

$repoRoot = Split-Path -Parent $PSScriptRoot
if (-not $EnvironmentFile) {
    $EnvironmentFile = Join-Path $repoRoot "config\environments\production.api.env"
}

& "$PSScriptRoot\validate-prod-api-config.ps1" -EnvironmentFile $EnvironmentFile

$values = Read-DotEnv $EnvironmentFile

foreach ($entry in $values.GetEnumerator()) {
    [Environment]::SetEnvironmentVariable($entry.Key, $entry.Value, "Process")
}

$apiDir = Join-Path $repoRoot "apps\api"
Write-Host ""
Write-Host "Starting DYNETIC WMS API against fulfilment_prod."
Write-Host "apps\api\.env is NOT being modified."
Write-Host "Stop with Ctrl+C."
Write-Host ""

Push-Location $apiDir
try {
    npm run dev
}
finally {
    Pop-Location
}
