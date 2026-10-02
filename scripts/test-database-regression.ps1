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
function Invoke-DyneticPsqlRegression {
    param(
        [Parameter(Mandatory=$true)][string]$RelativePath,
        [Parameter(Mandatory=$true)][string]$FailureLabel
    )

    $SqlPath = Join-Path $Root $RelativePath
    $StdOut = [IO.Path]::GetTempFileName()
    $StdErr = [IO.Path]::GetTempFileName()

    try {
        $Arguments = "-U `"$DbUser`" -d `"$Database`" -v ON_ERROR_STOP=1 -P pager=off -f `"$SqlPath`""

        $Process = Start-Process `
            -FilePath $Psql `
            -ArgumentList $Arguments `
            -Wait `
            -PassThru `
            -NoNewWindow `
            -RedirectStandardOutput $StdOut `
            -RedirectStandardError $StdErr

        if (Test-Path $StdOut) {
            Get-Content $StdOut | ForEach-Object { Write-Host $_ }
        }

        if (Test-Path $StdErr) {
            Get-Content $StdErr | ForEach-Object { Write-Host $_ }
        }

        if ($Process.ExitCode -ne 0) {
            throw "$FailureLabel failed: $RelativePath (psql exit code $($Process.ExitCode))"
        }
    }
    finally {
        Remove-Item $StdOut -Force -ErrorAction SilentlyContinue
        Remove-Item $StdErr -Force -ErrorAction SilentlyContinue
    }
}

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
 'database\tests\012_website_catalogue_smoke_test.sql'
)
$Fixtures=@(
 'database\tests\025_finatics_checkout_test_fixture.sql'
)

$TestsAfterFixture=@(
 'database\tests\013_website_checkout_order_api_test.sql',
 'database\tests\014_website_domain_v2_test.sql',
 'database\tests\015_dynetic_wms_system_version_test.sql',
 'database\tests\016_website_api_v3_test.sql',
 'database\tests\017_schema_contract_regression.sql',
 'database\tests\018_order_interface_negative_regression.sql',
 'database\tests\019_inventory_reconciliation_regression.sql',
 'database\tests\020_reservation_expiry_regression.sql',
 'database\tests\021_payment_failure_expiry_regression.sql',
 'database\tests\022_payment_security_idempotency_regression.sql',
 'database\tests\023_checkout_matrix_regression.sql',
 'database\tests\024_order_id_generation_regression.sql',
 'database\tests\026_checkout_customer_validation_regression.sql',
 'database\tests\027_checkout_address_length_regression.sql',
 'database\tests\028_admin_rbac_regression.sql',
 'database\tests\029_admin_operations_control_plane_regression.sql',
 'database\tests\030_admin_workbench_privileges_regression.sql',
 'database\tests\031_admin_control_plane_runtime_privileges_regression.sql',
 'database\tests\032_multi_site_order_foundation_regression.sql',
 'database\tests\033_multi_site_source_contract_regression.sql',
 'database\tests\034_admin_operational_backbone_regression.sql',
 'database\tests\035_admin_operational_workflow_contract_regression.sql',
 'database\tests\036_return_refund_idempotency_hardening_regression.sql',
 'database\tests\037_admin_return_case_runtime_privileges_regression.sql',
 'database\tests\038_dynetic_wms_0_3_18_release_regression.sql'
)
$passed=0

foreach($Test in $TestsBeforeFixture){
 Write-Host "[DB TEST] $Test"
 Invoke-DyneticPsqlRegression -RelativePath $Test -FailureLabel "Regression"
 $passed++
}

foreach($Fixture in $Fixtures){
 Write-Host "[DB FIXTURE] $Fixture"
 Invoke-DyneticPsqlRegression -RelativePath $Fixture -FailureLabel "Fixture"
}

foreach($Test in $TestsAfterFixture){
 Write-Host "[DB TEST] $Test"
 Invoke-DyneticPsqlRegression -RelativePath $Test -FailureLabel "Regression"
 $passed++
}

$totalTests=$TestsBeforeFixture.Count+$TestsAfterFixture.Count

Write-Host ""
Write-Host "DYNETIC WMS DATABASE REGRESSION PASSED: $passed/$totalTests test files."
