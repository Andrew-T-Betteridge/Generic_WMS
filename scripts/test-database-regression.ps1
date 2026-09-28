param(
    [string]$Database='fulfilment_test',
    [string]$DbUser='postgres',
    [string]$HostName='localhost',
    [int]$Port=5432
)
# DYNETIC_TEST_WRAPPER_GUARD_BEGIN
. "$PSScriptRoot\Test-Safety.ps1"
$null = Assert-DyneticTestScriptSafety -ScriptPath $MyInvocation.MyCommand.Path -BoundParameters $PSBoundParameters
# DYNETIC_TEST_WRAPPER_GUARD_END
# DYNETIC_TEST_LOCALHOST_GUARD_BEGIN
$allowedTestHosts=@('localhost','127.0.0.1','::1')

if($HostName -notin $allowedTestHosts){
    throw "TEST regression safety guard blocked non-local PostgreSQL host '$HostName'."
}
# DYNETIC_TEST_LOCALHOST_GUARD_END

$ErrorActionPreference='Stop'
$Psql='C:\Program Files\PostgreSQL\18\bin\psql.exe'
$Root=(Resolve-Path "$PSScriptRoot\..").Path

$TestsBeforeFixture=@(
 'database\tests\001_order_interface_smoke_test.sql',
 'database\tests\002_order_allocation_smoke_test.sql',
 'database\tests\003_allocation_edge_cases.sql',
 'database\tests\004_warehouse_execution_lifecycle.sql',
 'database\tests\005_warehouse_execution_edge_cases.sql',
 'database\tests\006_carrier_selection_smoke_test.sql',
 'database\tests\007_carrier_selection_edge_cases.sql',
 'database\tests\008_fulfilment_holds_smoke_test.sql',
 'database\tests\009_fulfilment_preference_edge_cases.sql',
 'database\tests\010_merge_consolidation_smoke_test.sql',
 'database\tests\011_merge_consolidation_edge_cases.sql',
 'database\tests\012_website_catalogue_smoke_test.sql',
 'database\tests\013_website_checkout_order_api_test.sql',
 'database\tests\014_website_domain_v2_test.sql',
 'database\tests\015_dynetic_wms_system_version_test.sql',
 'database\tests\016_website_api_v3_test.sql',
 'database\tests\017_schema_contract_regression.sql',
 'database\tests\018_order_interface_negative_regression.sql',
 'database\tests\019_inventory_reconciliation_regression.sql',
 'database\tests\020_reservation_expiry_regression.sql',
 'database\tests\021_payment_failure_expiry_regression.sql',
 'database\tests\022_payment_security_idempotency_regression.sql'
)

$Fixtures=@(
 'database\tests\025_finatics_checkout_test_fixture.sql'
)

$TestsAfterFixture=@(
 'database\tests\023_checkout_matrix_regression.sql',
 'database\tests\024_order_id_generation_regression.sql',
 'database\tests\026_checkout_customer_validation_regression.sql',
 'database\tests\027_checkout_address_length_regression.sql',
 'database\tests\028_admin_rbac_regression.sql',
 'database\tests\029_admin_operations_control_plane_regression.sql'
)

$passed=0

foreach($Test in $TestsBeforeFixture){
 Write-Host "[DB TEST] $Test"
 & $Psql -X -h $HostName -p $Port -U $DbUser -d $Database -v ON_ERROR_STOP=1 -P pager=off -f (Join-Path $Root $Test)
 if($LASTEXITCODE -ne 0){throw "Regression failed: $Test"}
 $passed++
}

foreach($Fixture in $Fixtures){
 Write-Host "[DB FIXTURE] $Fixture"
 & $Psql -X -h $HostName -p $Port -U $DbUser -d $Database -v ON_ERROR_STOP=1 -P pager=off -f (Join-Path $Root $Fixture)
 if($LASTEXITCODE -ne 0){throw "Fixture failed: $Fixture"}
}

foreach($Test in $TestsAfterFixture){
 Write-Host "[DB TEST] $Test"
 & $Psql -X -h $HostName -p $Port -U $DbUser -d $Database -v ON_ERROR_STOP=1 -P pager=off -f (Join-Path $Root $Test)
 if($LASTEXITCODE -ne 0){throw "Regression failed: $Test"}
 $passed++
}

$totalTests=$TestsBeforeFixture.Count+$TestsAfterFixture.Count

Write-Host ""
Write-Host "DYNETIC WMS DATABASE REGRESSION PASSED: $passed/$totalTests test files."
