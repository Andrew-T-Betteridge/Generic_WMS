# Merge evaluate record-alias hotfix

The error:

`record "oh" is not assigned yet`

was caused by a PL/pgSQL variable named `oh` colliding with the SQL table alias
`oh` used for `core.ORDER_HEADER`.

PostgreSQL resolved `oh.CUSTOMER_ID` as the unassigned PL/pgSQL RECORD variable
instead of the SQL alias.

This replacement:

- removes the unused `oh RECORD` declaration;
- renames the SQL alias to `hdr`;
- changes no merge behaviour.

## Apply

Extract over the repository root and replace:

`database/functions/core/EVALUATE_CONTAINER_MERGE.sql`

Then rerun only the clean verification:

```powershell
.\scripts\verify-clean-build.ps1
```
