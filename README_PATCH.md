# Generic WMS Allocation Patch

Extract over the repository root.

Then apply to `fulfilment_dev`:

```powershell
.\scripts\apply-allocation.ps1
```

This patch replaces the two key definitions, adds `core.ALLOCATION`, adds the V1 allocation function, and includes migration `0007_add_allocation.sql`.

I have not overwritten the existing build orchestration scripts because their current contents were not supplied. Add `database\tables\core\ALLOCATION.sql` to the normal clean-build table sequence and `database\functions\core\ALLOCATE_ORDER.sql` after the table exists.
