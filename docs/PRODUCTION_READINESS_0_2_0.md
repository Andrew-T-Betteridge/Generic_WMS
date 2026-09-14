# DYNETIC WMS 0.2.0 - Production Readiness

The database production baseline has already been created and smoke-tested.

This patch adds the next production controls without turning real traffic or live payments on.

## Production environment separation

Copy:

`config/environments/production.api.env.example`

to:

`config/environments/production.api.env`

The populated file contains secrets and must not be committed.

The production API runner loads that file into **process environment variables** and does not overwrite `apps/api/.env`, so the existing TEST setup stays intact.

Production authentication is deliberately restricted to `OIDC`. `DEV_HS256` is rejected by the validation script.

## Production API validation

From the repository root:

```powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
.\scripts\validate-prod-api-config.ps1
```

It checks the PROD DB target, OIDC configuration, HTTPS storefront origin, guest-token secret and Stripe key type.

It is valid to leave Stripe production keys blank until live payments are intentionally enabled.

## Starting a local production-configured API

After the production environment file is complete:

```powershell
.\scripts\start-prod-api-local.ps1
```

This starts the existing API against `fulfilment_prod` without modifying `apps/api/.env`.

Then, from another PowerShell window:

```powershell
cd "C:\Users\atbet\OneDrive\Repository\Business Docs\Generic WMS"
.\scripts\test-prod-api-readonly.ps1
```

That HTTP check performs GET requests only:

- `/health`
- `/api/system/version`
- `/api/catalog/products`
- the real fry-tray product endpoint

No order/payment/inventory write is made.

## Production database backup

Before every production deployment:

```powershell
.\scripts\backup-prod.ps1
```

It uses PostgreSQL 18 `pg_dump` in custom format and writes a timestamped `.backup` file beneath `backups\`.

Do not commit database backups.

## Overall readiness

```powershell
.\scripts\verify-prod-readiness.ps1
```

This reruns the existing read-only database smoke check and, when a populated production API environment exists, validates that config too.

## Release tag

Once these files are committed and Git is clean:

```powershell
.\scripts\create-release-tag.ps1
git push origin dynetic-wms-v0.2.0
```

That marks the exact backend/database production baseline that passed TEST, external Stripe sandbox regression and PROD smoke checks.

## What is intentionally NOT done yet

- No DNS change.
- No production website traffic.
- No live Stripe key.
- No live Stripe webhook endpoint.
- No production payment.
- No replacement of the TEST `.env`.
- No invented production inventory.

Those are later go-live steps, after the Lovable client is built and acceptance-tested against the API.
