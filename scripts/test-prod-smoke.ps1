# DYNETIC WMS
# Production test execution is intentionally disabled.
#
# POLICY:
#   No regression, smoke, load, concurrency, checkout, API, database or
#   application test may execute against PROD.
#
# This file remains in the repository as a hard safety stop so that any
# existing automation or operator attempting to invoke test-prod-smoke.ps1
# fails before making a database connection or issuing any query.

$ErrorActionPreference = "Stop"

Write-Host ""
Write-Host "====================================================" -ForegroundColor Red
Write-Host "SAFETY STOP - PROD TEST EXECUTION IS DISABLED" -ForegroundColor Red
Write-Host "====================================================" -ForegroundColor Red
Write-Host "No test has been run." -ForegroundColor Yellow
Write-Host "No database connection has been opened." -ForegroundColor Yellow
Write-Host "No SQL has been executed." -ForegroundColor Yellow
Write-Host ""
Write-Host "DYNETIC policy allows tests only against DEV or TEST." -ForegroundColor Yellow
Write-Host "Use non-production validation before deployment and read-only operational monitoring after deployment." -ForegroundColor Yellow
Write-Host "====================================================" -ForegroundColor Red
Write-Host ""

throw "SAFETY STOP: test-prod-smoke.ps1 is permanently disabled. Tests must not run against PROD."
