# DYNETIC WMS System Version

The generic warehouse platform is now branded **DYNETIC WMS**.

Current development baseline:

- Product code: `DYNETIC_WMS`
- Product name: `DYNETIC WMS`
- Version: `0.1.0`
- Release channel: `DEVELOPMENT`

Version history is stored in:

`config.SYSTEM_VERSION`

Only one row per product may have `IS_CURRENT = TRUE`.

The public/server-safe API function is:

`api.GET_SYSTEM_VERSION()`

HTTP endpoint:

`GET /api/system/version`

The `/health` endpoint also reports the DYNETIC WMS service name and current version.

## Versioning convention

Use semantic versions:

`MAJOR.MINOR.PATCH`

During active pre-production development, keep the major version at `0`.

Examples:

- `0.1.0` initial development baseline
- `0.2.0` next meaningful feature release
- `0.2.1` bug-fix release
- `1.0.0` first production-stable release

Each future release should add/update the version row through a migration rather than editing production data manually.
