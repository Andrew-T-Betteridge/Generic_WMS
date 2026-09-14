# DYNETIC WMS Stripe E2E psql user fix

The Stripe E2E script was invoking `psql` without `-U`, so PostgreSQL defaulted to the
current Windows account (`atbet`) instead of the configured database user.

This patch changes the script to read and use:

- `DB_HOST`
- `DB_PORT`
- `DB_USER`

from `apps/api/.env`.

With the current setup this means the command connects as the configured PostgreSQL user
and can use the existing `pgpass.conf` entry, so it should not prompt for a password.

## Apply

Extract over:

`C:\Users\atbet\OneDrive\Repository\Business Docs\Generic WMS`

Then, from the repository root:

```powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
.\scripts\test-stripe-e2e.ps1
```

Keep the API and Stripe listener running in their separate windows.
