# DYNETIC WMS environments and regression workflow

## Databases

- `fulfilment_dev` — active development. Changes are tried here first.
- `fulfilment_test` — controlled integration/UAT database. Rebuilt from repository source and used for regression.
- `fulfilment_prod` — production. Never dropped/recreated by automation in this repository.

Authentication remains outside the database. PostgreSQL credentials should use `pgpass.conf` locally or environment/secret management on hosted infrastructure. Do not commit passwords.

## Normal change flow

1. Develop and smoke-test in DEV.
2. Commit all schema/function/API changes to Git.
3. Run `scripts/test-full-regression.ps1`. This destroys/recreates only `fulfilment_test`, clean-builds it, then runs the SQL regression suite.
4. Run the API against TEST and optionally run `scripts/test-full-regression.ps1 -IncludeHttp`.
5. Only after the exact commit/release is green in TEST should PROD deployment be approved.

## Environment commands

From repository root:

```powershell
.\scripts\create-dev-db.ps1
.\scripts\deploy-to-dev.ps1

.\scripts\create-test-db.ps1
.\scripts\deploy-to-test.ps1
.\scripts\test-full-regression.ps1

# First-time PROD creation only; deliberately guarded.
.\scripts\create-prod-db.ps1 -IUnderstandThisCreatesProduction

# PROD deployment is deliberately double-confirmed.
.\scripts\deploy-to-prod.ps1 -ApprovedForProduction -TestRegressionPassed
```

## Production safety

`create-prod-db.ps1` never drops an existing production database. `deploy-to-prod.ps1` refuses to run unless both approval switches are supplied and the database already exists. Before real production use, add infrastructure-level backups/snapshots and release tagging; repository scripts cannot replace database backup policy.

## Regression coverage

The suite retains all existing tests and adds contract, interface-negative, inventory reconciliation, reservation-expiry, payment-failure/expiry and payment ownership/idempotency tests. Every SQL test uses `BEGIN`/`ROLLBACK`, so regression fixtures do not remain in TEST.

`test-full-regression.ps1` intentionally leaves `fulfilment_test` available after a successful run so it can be used for API/UAT testing. The next run recreates it from scratch.

## HTTP tests

HTTP tests require a running API. For TEST, point the API DB configuration at `fulfilment_test`, use local/test authentication and Stripe test mode, restart the API, then run:

```powershell
.\scripts\test-full-regression.ps1 -IncludeHttp
```

Never point a local test API at `fulfilment_prod`.
