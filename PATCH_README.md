# DYNETIC WMS Production Readiness V1

This patch takes the next several steps after the successful `fulfilment_prod` smoke test.

Adds:

- `config/environments/production.api.env.example`
- `scripts/validate-prod-api-config.ps1`
- `scripts/start-prod-api-local.ps1`
- `scripts/test-prod-api-readonly.ps1`
- `scripts/backup-prod.ps1`
- `scripts/verify-prod-readiness.ps1`
- `scripts/create-release-tag.ps1`
- `docs/PRODUCTION_READINESS_0_2_0.md`
- `docs/GITIGNORE_PRODUCTION_ADDITIONS.txt`

It does **not** enable live traffic or live Stripe payments.

Recommended immediate sequence:

1. Extract over the repository.
2. Add the two recommended `.gitignore` entries.
3. Run `.\scripts\backup-prod.ps1`.
4. Run `.\scripts\verify-prod-readiness.ps1`.
5. Commit/push this production baseline.
6. Create/push `dynetic-wms-v0.2.0`.

OIDC and live Stripe values can remain unconfigured until the external production services are deliberately enabled.
