param(
    [string]$Database = "fulfilment_dev",
    [string]$DbUser = "postgres"
)
$ErrorActionPreference = "Stop"
& "$PSScriptRoot\apply-foundation.ps1" -Database $Database -DbUser $DbUser
if ($LASTEXITCODE -ne 0) { throw "Foundation build failed." }
& "$PSScriptRoot\apply-core.ps1" -Database $Database -DbUser $DbUser
if ($LASTEXITCODE -ne 0) { throw "Core build failed." }
& "$PSScriptRoot\apply-supporting-tables.ps1" -Database $Database -DbUser $DbUser
if ($LASTEXITCODE -ne 0) { throw "Supporting build failed." }
& "$PSScriptRoot\apply-allocation.ps1" -Database $Database -DbUser $DbUser
if ($LASTEXITCODE -ne 0) { throw "Allocation build failed." }
& "$PSScriptRoot\apply-warehouse-execution.ps1" -Database $Database -DbUser $DbUser
if ($LASTEXITCODE -ne 0) { throw "Warehouse execution build failed." }
Write-Host ""
Write-Host "Full Generic WMS database build completed successfully."
