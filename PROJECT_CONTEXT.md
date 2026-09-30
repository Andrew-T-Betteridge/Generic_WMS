# DYNETIC Generic WMS - Project Context

**Last updated:** 2026-09-30
**Current development target:** 0.3.18
**Last reviewed against Git commit:** 9159de75d5196f57a0aca637eca918141318a2ee
**Status:** Active development - 0.3.18 operational Admin expansion

> IMPORTANT FOR FUTURE CHATGPT SESSIONS / DEVELOPERS
>
> Read this document before modifying this repository.
> Compare Last updated and Last reviewed against Git commit with the current repository.
> If this document is materially older than the current source, treat it as architectural guidance and verify changed implementation against source before modifying anything.
> Update this document in the same commit whenever architecture, deployment, release state, important workflows, schema conventions, production safety rules or major implementation decisions change.

## 1. Product

DYNETIC Generic WMS is the reusable warehouse/order-management platform.
FINatics Aquatics is the first deployed client/brand, not the architecture of the WMS.
The Generic WMS Admin must remain reusable for unrelated businesses, clients, sites and products.

Main application areas:

- apps/api - Generic WMS API/backend
- apps/admin - Generic WMS Admin SPA
- database - PostgreSQL schema, functions, migrations and regression tests
- FINatics storefront is a separate application/repository

## 2. Core tenancy architecture

### CLIENT

CLIENT is the tenant/business/stock owner.

### SITE

SITE is an independent physical or logical operating/fulfilment location.
SITE is NOT a child of CLIENT.
Do not add CLIENT_ID ownership to SITE.

### CLIENT_SITE

config.CLIENT_SITE describes which CLIENT/SITE combinations are operationally applicable.
It is applicability, not ownership.
One physical site may serve multiple clients.

Current FINatics operational SITE_ID is FINATICS.

### Scope rules

- SKU is CLIENT scoped.
- Inventory is CLIENT + SITE scoped.
- Orders are CLIENT + SITE scoped.
- Pre-advice is CLIENT + SITE scoped.
- Carrier/rate configuration may have CLIENT/SITE applicability.
- Communications branding/templates/senders are CLIENT configurable.
- Storefront/API consumers identify the appropriate CLIENT/SITE context.
- Server-side authorization owns CLIENT/SITE scope.
- Never trust browser-supplied tenant identifiers as authorization.
- Avoid unsafe ORDER_ID-only access.

## 3. Order identity

Human order references are generated centrally by the WMS/API.
Format uses the first four characters of CLIENT followed by the numeric sequence.
Example: FINA-0000123456.
Storefronts must not authoritatively generate unique order IDs.

## 4. Admin architecture

Admin is an internal authorized application.
Authentication/authorization uses Auth0/OIDC plus server-side DYNETIC RBAC.
There is no public Admin registration.

Lovable/Pixel Perfect is the visual/UX authority for Admin.
Generic WMS source/API/database remain the functional, security and data authority.

Do not introduce:

- Supabase or replacement databases
- direct PostgreSQL access from the browser
- duplicated backend business logic in React
- mock production functionality
- hard-coded FINatics behaviour in Generic Admin
- speculative endpoints that do not exist

## 5. Admin operational philosophy

The Admin should answer: WHAT NEEDS DOING NOW?

The Control Centre is an operational work queue, not a daily sales dashboard.
Outstanding work remains visible regardless of which day the order was created.

Primary operational concepts:

- outstanding/live orders
- orders needing attention
- open picks
- actionable payment exceptions
- open returns/claims
- operational exceptions
- failed notifications where action is genuinely required

Historical failed/abandoned payment attempts must not dominate the operational dashboard.

## 6. Order status behaviour

Known fulfilment statuses currently used by Admin/source include:

- UNALLOCATED
- RESERVED
- PART_ALLOCATED
- ALLOCATED
- PICKING
- PACKED
- SHIPPED
- DELIVERED
- CANCELLED

Derived operational states also exist, including READY_TO_PACK and PART_PICKED.

Admin Orders should support multiple statuses simultaneously.
The default operational view should focus on live/outstanding orders and exclude terminal noise.

Terminal fulfilment states currently treated as non-live:

- SHIPPED
- DELIVERED
- CANCELLED

If the status model changes, verify this list against the database/functions before changing presets.

## 7. Payments

Known payment states include CREATED, PENDING, AUTHORISED, PAID, FAILED, CANCELLED, REFUNDED and PART_REFUNDED.

Payment history belongs in payment/order/customer detail.
The Control Centre should surface payment states only when they require operational action or block/affect a valid order.

Refund operations require stable idempotency/operation IDs.
Refund accounting must be concurrency-safe.
Do not weaken the 0.3.18 refund locking/idempotency protections.

## 8. Returns and claims

Return/claim workflow should start from the original outbound order.

Preferred workflow:

1. Find outbound order/customer.
2. Inspect order and lines.
3. Select item(s) and quantity.
4. Choose Return or Claim.
5. Capture reason/details.
6. Capture expected resolution such as refund/replacement where supported.
7. Submit with stable operation ID.
8. Track the case with deep links back to the original order.

Return operation IDs are persisted and must remain idempotent.

## 9. Customers

0.3.18 source contains Admin customer list/detail endpoints.
If production Admin reports /api/admin/customers 404 while source contains the endpoint, check deployed API release before changing the frontend.

## 10. Audit

Audit must scale to large record counts.
Use server-side filtering and pagination.

Target UX:

1. Select audited entity/table.
2. Select relevant searchable field/column.
3. Enter value/operator.
4. Optionally filter date/action/user.
5. Display paginated results.

Use business-facing labels while mapping to real backend fields.
Do not invent before/after values if audit storage did not capture them.

## 11. Carrier rates

Money must be displayed in human-readable currency.
Never assume whether a stored rate is minor units or decimal currency without verifying the source/schema contract.
Admin should show currency symbol/code clearly, e.g. GBP / £ where supported by the stored contract.

## 12. Production safety

Production contains genuine customer/payment/order activity.

During investigation or Admin deployment DO NOT casually run:

- database regression suites
- migrations
- destructive SQL
- test inserts
- test orders
- payment tests
- inventory mutation tests
- Git reset/clean/checkout against the production working tree

Prefer read-only inspection where production inspection is genuinely necessary.

## 13. Production topology

Production host: 89.167.116.81
SSH user: andrew
Generic WMS repo path: /opt/dynetic/Generic_WMS
Production database: fulfilment_prod

Admin public host: admin.finaticsaquatics.co.uk
API public host: api.finaticsaquatics.co.uk

Nginx currently serves Admin from:

/opt/dynetic/Generic_WMS/apps/admin/dist

Production API is release-based through systemd override rather than necessarily executing the source working tree.
Always inspect the active systemd release WorkingDirectory before assuming the checked-out repo is the running API.

## 14. Production Git warning

The production Generic WMS repository has previously been detached/divergent and contained local modifications/untracked deployment backups.
Do NOT blindly git pull/reset/checkout/clean production.
Admin static deployment should use a controlled built artifact and explicit switch/copy procedure.

## 15. Release discipline

Existing release tags are immutable.
Never move/delete/recreate an existing release tag.

Known Admin immutable releases:

- finatics-admin-v0.3.15.1
- finatics-admin-v0.3.15.2
- finatics-admin-v0.3.16
- finatics-admin-v0.3.17

0.3.18 is currently a development target and must not be called an immutable release until the coherent package is validated and committed.

## 16. Working conventions for ChatGPT-assisted development

User runs Windows PowerShell locally.
Repository:

C:\Users\atbet\OneDrive\Repository\Business Docs\Generic WMS

Every executable PowerShell block supplied to the user MUST begin with Clear-Host.
Prefer large coherent command batches rather than one-command-at-a-time interaction.
Every command block should be standalone and begin from Windows PowerShell.
If Linux is required, invoke SSH from the Windows PowerShell block.
Do not make the user manually keep track of Windows versus Linux sessions.
Never put exit or exit 1 into supplied PowerShell blocks.
Avoid PowerShell here-strings; they have previously left the terminal stuck at the continuation prompt.
Avoid piping PowerShell-generated multiline CRLF scripts directly into remote bash.
Prefer individual SSH commands or controlled LF-only transferred scripts.
Generated diagnostics/captures should go to C:\Users\atbet\Downloads, not TEMP.


### 0.3.18 operational work-queue pass

- Orders API supports validated comma-separated multi-status fulfilment filtering.
- Orders UI defaults to operationally open fulfilment states and provides presets plus individual status selection.
- Header fulfilment states observed in source include UNALLOCATED, RESERVED, PART_ALLOCATED, ALLOCATED, PICKING, PART_PICKED, PICKED, PACKED, SHIPPED, DELIVERED and CANCELLED.
- READY_TO_PACK is a derived workbench/allocation concept and is not treated as an ORDER_HEADER fulfilment status.
- Control Centre is an outstanding-work queue rather than a today-only sales dashboard.
- SHIPPED, DELIVERED and CANCELLED are treated as terminal for the operational outstanding-order view.
- Dashboard payment attention currently means non-terminal orders with PAYMENT_STATUS=PENDING; failed standalone payment attempts are not surfaced as permanent operational work.

## 17. Current 0.3.18 development objectives

- Operational Control Centre
- Outstanding/live order workload
- Multi-status Orders filtering and presets
- Persistent Orders filter state
- Better order/customer/reference searching
- Actionable payment exception visibility
- Outbound-order-first Returns/Claims workflow
- Customer API/UI alignment
- Catalogue Create Product contract verification
- Carrier-rate currency presentation
- Scalable entity/field-driven Audit Trail
- Client/Site authorization and applicability consistency
- Regression coverage for the above

## 18. Maintenance rule

This file is part of the product.
When a change materially alters architecture, schema conventions, operational behaviour, deployment, release state, production safety or major workflow decisions, update PROJECT_CONTEXT.md in the SAME COMMIT.

Before committing a release:

1. Update Last updated.
2. Update Current development target/release state.
3. Update Last reviewed against Git commit where practical.
4. Remove obsolete current-work notes.
5. Preserve historical safety lessons that remain relevant.

### 0.3.18 functional UI pass 3

- Control Centre uses operational outstanding orders rather than orders created today.
- Payment attention is the count of PENDING-payment orders requiring attention, not paid revenue.
- Open pick count uses current OPEN/PART_PICKED task statuses.
- Returns & Claims is outbound-order-first: operators can search an existing outbound order before opening a case.
- The create-case modal accepts a selected outbound order and continues to use the existing stable operationId contract.
- Existing return/claim cases remain independently searchable and manageable.
- Audit metadata is loaded from authorised audit history rather than hard-coded entity/action lists.
- Audit supports server-side entity type, entity ID contains, action, changed-by, inclusive date range, limit and offset filters.
- Audit displays field-level differences derived only from BEFORE_DATA and AFTER_DATA.
- No line-level return item/quantity workflow has been invented; that remains dependent on a proven backend contract.

### 0.3.18 functional pass 4

- Restored persisted return/claim idempotency after source recovery removed the Batch 5 route implementation.
- Return creation requires a stable operationId or Idempotency-Key.
- RETURN_CASE.OPERATION_ID is the persisted idempotency key introduced by migration 0039.
- Concurrent duplicate return creation is protected by the CLIENT_ID + OPERATION_ID unique contract.
- Product creation requires CATEGORY_CODE; the Admin create modal must never submit a product without one.
- Added an authorised Admin product-category read endpoint backed by core.PRODUCT_CATEGORY.
- Create Product now loads active configured categories rather than inventing or hard-coding category values.
- Product create continues to use backend defaults/contracts for fields not explicitly entered.

### 0.3.18 functional pass 5

- Return/claim lifecycle UI exposes the full persisted status set including AWAITING_CUSTOMER.
- AWAITING_CUSTOMER is treated as an attention/warning state in both legacy control-plane pills and the shared StatusBadge.
- Notification alert preference is now stored under the generic dynetic-admin-alerts-enabled key.
- Existing finatics-alerts-enabled browser preferences are read once as a backwards-compatible fallback and migrated when alerts are enabled again.
- Removed stale backend-version wording from the Delivery read-only screen.

### 0.3.18 functional pass 6

- RETURN_CASE_LINE is an existing 0.3.18 source-backed table and supports item-level return/claim intake.
- Return creation can now persist selected ORDER_LINE records with quantity, issue type, expected resolution, refund amount and notes.
- Item-level return creation is atomic with the return-case header.
- Selected return quantities are validated against the original ORDER_LINE quantity and existing non-rejected return-case quantities.
- Return creation remains persistently idempotent using CLIENT_ID + OPERATION_ID.
- GET /api/admin/returns/:id returns the case header plus its persisted RETURN_CASE_LINE rows.
- New Return / Claim now loads the authoritative order detail, presents its order lines and requires at least one positive quantity.
- Existing return cases display their recorded item-level lines when opened.
- Header-only legacy return cases remain readable and are not rewritten.

### 0.3.18 release hardening pass 7

- Migration 0040 formalises runtime write privileges required by the Admin return/claim workflow.
- Runtime role requires SELECT/INSERT/UPDATE on core.RETURN_CASE.
- Runtime role requires SELECT/INSERT on core.RETURN_CASE_LINE.
- Existing migration 0037 is not rewritten; 0040 is a forward-only privilege extension.
- Regression 037 validates the item-level RETURN_CASE_LINE schema contract and required runtime privileges.
- API 0.3.18 must not be deployed before migrations 0038, 0039 and 0040 have been validated in preflight and included in the production deployment plan.

### 0.3.18 release metadata completion

- API package version is 0.3.18 and must match the immutable dynetic-wms-v0.3.18 release tag.
- Migration 0041 registers DYNETIC WMS 0.3.18 as the current database system version.
- Production release manifest is 0038 -> 0039 -> 0040 -> 0041.
- Fresh-install manifest includes runtime privilege migrations 0036/0037 and the complete 0.3.18 migration chain.
- Regression 038 validates the final 0.3.18 release/version contract.
- No immutable 0.3.18 tag is created until disposable database preflight succeeds.

### 0.3.18 legacy SITE migration preflight fix

- Disposable database preflight exposed a real 0038 upgrade-order defect from the 0.3.14/0.3.15 SITE schema.
- Legacy core.SITE still carries CLIENT_ID NOT NULL before the 0.3.18 migration.
- 0038 now creates CLIENT_SITE and preserves SITE/CLIENT applicability before dropping SITE.CLIENT_ID.
- Only after ownership is removed does 0038 bootstrap missing independent SITE masters from LOCATION/INVENTORY evidence.
- No dummy client, hard-coded FINatics client or global HQ fallback is introduced.
- The failed 0038 preflight transaction rolled back and production was not referenced or modified.

### 0.3.18 database preflight passed

- Disposable 0.3.18 database upgrade preflight completed successfully on 2026-09-30.
- Legacy baseline was upgraded through 0035, 0036, 0037, corrected 0038, 0039, 0040 and 0041.
- Corrected 0038 preserved SITE/CLIENT applicability before removing legacy SITE.CLIENT_ID.
- Database reported DYNETIC WMS 0.3.18.
- Regressions 015, 030, 031, 032, 033 and 034 passed during the first database gate.
- Regressions 035, 036, 037 and 038 passed during the final database gate.
- SITE is an independent master and CLIENT_SITE applicability passed integrity validation.
- ORDER_HEADER and INVENTORY contain valid active CLIENT/SITE applicability.
- RETURN_CASE.OPERATION_ID and runtime privilege contracts passed.
- Exactly one current DYNETIC_WMS system version remains.
- No client has multiple active default fulfilment sites.
- Disposable preflight database was dropped after successful validation.
- Production database was not referenced or modified.
- Final validated functional source commit: b528e9b9f0442d2a1e902e4e913f025ae2ca4f91.

### 0.3.18 production deployment complete

- Immutable release: dynetic-wms-v0.3.18.
- Release commit: f73197c7abaa01f06cc0bd74ec64b3c053649201.
- Production database upgraded successfully to DYNETIC WMS 0.3.18.
- Production migration set: 0038, 0039, 0040 and 0041.
- No database regression tests or test fixtures were executed against production.
- CLIENT/SITE order and inventory integrity checks returned zero invalid rows.
- Production API runs from /opt/dynetic/releases/dynetic-wms-v0.3.18/apps/api.
- Public and local API version/health checks passed.
- Tagged 0.3.18 Admin bundle is live under the stable nginx Admin root.
- FINatics storefront service remained active and was not deployed as part of the WMS release.
- Systemd release selection was canonicalised to dynetic-api.service.d/release.conf pointing at 0.3.18.
- Temporary competing 99-dynetic-release.conf and zzzz-dynetic-wms-0.3.18.conf overrides were removed after backup.
- Pre-deployment and post-deployment backups are retained under /home/andrew/dynetic-backups/0.3.18.
