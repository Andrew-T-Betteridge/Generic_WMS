# DYNETIC WMS regression runner PowerShell fix

The regression tests themselves passed, including:

- Payment failure/expiry
- Payment security/idempotency

The final summary output then failed because Windows PowerShell 5.1 does not support using
`if (...) { ... } else { ... }` directly as an expression inside `Write-Host (...)`.

This patch changes the summary code to assign the result to `$httpStatus` first and then
prints it.

No database or application logic changes are included.

## Apply

Extract over the repository root:

`C:\Users\atbet\OneDrive\Repository\Business Docs\Generic WMS`

Then rerun:

```powershell
.\scripts\test-full-regression.ps1
```
