# Carrier Selection smoke-test location hotfix

The clean-build failure was caused by the smoke test depending on an existing
`core.LOCATION`.

Earlier test fixtures do not persist because those tests run inside
`BEGIN / ROLLBACK`, so a clean database can legitimately contain no LOCATION
rows when carrier test 006 starts.

This replacement makes test 006 fully self-contained by inserting:

`CARR-TEST-LOC`

with all mandatory LOCATION fields before inserting SHIPPING_MANIFEST.

No production schema/function change is required.

## Apply

Extract over the repository root and replace:

`database/tests/006_carrier_selection_smoke_test.sql`

Then rerun:

```powershell
.\scripts\verify-clean-build.ps1
```

You do not need to rerun `build-database.ps1` first because the previous
production build already completed; this failure occurred only in the temporary
clean-build test database.
