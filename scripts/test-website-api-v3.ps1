param([string]$Database="fulfilment_dev",[string]$DbUser="postgres")
# DYNETIC_TEST_WRAPPER_GUARD_BEGIN
. "$PSScriptRoot\Test-Safety.ps1"
$null = Assert-DyneticTestScriptSafety -ScriptPath $MyInvocation.MyCommand.Path -BoundParameters $PSBoundParameters
# DYNETIC_TEST_WRAPPER_GUARD_END

$ErrorActionPreference="Stop"
$Psql="C:\Program Files\PostgreSQL\18\bin\psql.exe"
$Root=(Resolve-Path "$PSScriptRoot\..").Path
$Test="database\tests\016_website_api_v3_test.sql"

& $Psql -U $DbUser -d $Database -v ON_ERROR_STOP=1 -P pager=off -f (Join-Path $Root $Test)
if($LASTEXITCODE -ne 0){throw "Website/API V3 SQL test failed."}
Write-Host "DYNETIC WMS Website/API V3 SQL tests passed."
