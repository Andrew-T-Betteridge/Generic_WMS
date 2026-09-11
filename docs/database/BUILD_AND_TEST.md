# Generic WMS Build and Test

## Full local build

```powershell
.\scripts\build-database.ps1
```

Build order:

1. foundation
2. refined core
3. supporting tables and interface processing
4. allocation migration/table/index/view/functions

## Full clean verification

```powershell
.\scripts\verify-clean-build.ps1
```

The command creates a temporary database, builds the whole repository, runs
order-interface tests and allocation tests, then removes the database.

To inspect the temporary database after a run:

```powershell
.\scripts\verify-clean-build.ps1 -KeepDatabase
```

## Allocation-only tests

```powershell
.\scripts\test-order-allocation.ps1
```

## Order-interface-only test

```powershell
.\scripts\test-order-interface.ps1
```

## Development database after repository changes

```powershell
.\scripts\build-database.ps1
```

Then run:

```powershell
.\scripts\test-order-interface.ps1
.\scripts\test-order-allocation.ps1
```
