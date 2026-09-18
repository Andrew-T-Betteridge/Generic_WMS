# DYNETIC database deployment guard

Fail-closed deployment path:
- Target must be DEV, TEST or PROD.
- Connected database identity is verified before SQL.
- Test/fixture/sample/demo/smoke/load SQL is rejected.
- psql runs with ON_ERROR_STOP=1.
- PROD additionally requires -ConfirmProductionRelease, committed tracked files, and a dynetic-wms-v* tag on HEAD.
- An empty manifest deploys nothing.

Workflow:
1. Run scripts/New-DatabaseDeployInventory.ps1
2. Review database/deploy/database-sql-inventory.txt
3. Populate database/deploy/release-manifest.txt with production-safe SQL in execution order
4. Run scripts/Verify-DeploymentSafety.ps1
5. Rehearse exact manifest in TEST
6. Commit/tag
7. Deploy same manifest to PROD, with no tests or fixtures in PROD
