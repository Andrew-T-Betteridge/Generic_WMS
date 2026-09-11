# Allocation 0007 canonical clean-build fix

This replaces:

`database/migrations/0007_add_allocation.sql`

## What happened

The previous view-dependency hotfix correctly stopped PostgreSQL from
re-running an unnecessary `ALTER COLUMN ... TYPE BIGINT`, but its
`CREATE TABLE core.ALLOCATION` definition did not match the existing
canonical file:

`database/tables/core/ALLOCATION.sql`

A persistent upgraded database could hide that mismatch because the table
already existed. A genuinely clean database exposed it when
`ALLOCATION.sql` tried to comment `ALLOCATION_DSTAMP`.

This replacement fixes both issues:

1. KEY type conversion only runs when genuinely required.
2. `core.ALLOCATION` is created with the original canonical Allocation V1
   columns, including `ALLOCATION_DSTAMP`.
3. Warehouse Execution migration `0008_warehouse_execution_v1.sql` remains
   responsible for adding `QTY_PICKED`, `QTY_RELEASED`, `STATUS`, etc.

## Run

Extract this ZIP over the Generic WMS repository root and replace the
existing migration file.

Your temporary clean-build database was already dropped by the failed test,
so simply run:

```powershell
.\scripts\verify-clean-build.ps1
```

There is no need to rebuild `fulfilment_dev` first.
