param([string]$Database="fulfilment_dev",[string]$DbUser="postgres")
# DYNETIC_TEST_WRAPPER_GUARD_BEGIN
. "$PSScriptRoot\Test-Safety.ps1"
$null = Assert-DyneticTestScriptSafety -ScriptPath $MyInvocation.MyCommand.Path -BoundParameters $PSBoundParameters
# DYNETIC_TEST_WRAPPER_GUARD_END

$ErrorActionPreference="Stop"; $Psql="C:\Program Files\PostgreSQL\18\bin\psql.exe"; $Test="database\tests\014_website_domain_v2_test.sql"; $Root=(Resolve-Path "$PSScriptRoot\..").Path
& $Psql -U $DbUser -d $Database -v ON_ERROR_STOP=1 -P pager=off -f (Join-Path $Root $Test)
if($LASTEXITCODE -ne 0){throw "Website Domain V2 test failed: $Test"}
Write-Host "Website Domain V2 tests passed."
