# DYNETIC WMS 0.3.14 — Backend-first Admin & Operations

This is a consolidated development release package. It supersedes the earlier
small 0.3.14 admin package. Do not install both.

## Scope

The frontend should be a presentation layer over guarded backend commands.

### Operations
- operational dashboard
- exception centre
- order search and full order inspector
- allowed-action endpoint
- safe header amendment
- pre-fulfilment line amendment only
- order notes
- allocate / deallocate / create picks / cancel
- stock availability, adjustment and safe whole-row stock movement
- pick queue + pick/short confirmation
- shipment queue + ship container
- payments + full/partial Stripe refund request ledger
- return / DOA / damage / wrong-item cases
- notification failures + retry
- failed order-interface inspection + retry
- audit search
- system health

### Commercial / inbound
- suppliers
- pre-advice read model
- promotions
- gift cards + immutable gift-card transaction ledger
- carrier/services/rates/delivery-zone read model
- reason codes / SLA configuration model

### Data model additions
- ORDER_NOTE
- CUSTOMER_NOTE
- RETURN_CASE / RETURN_CASE_LINE
- PAYMENT_REFUND
- GIFT_CARD_TRANSACTION
- INVENTORY_COUNT / INVENTORY_COUNT_LINE
- ADMIN_REASON_CODE
- ADMIN_OPERATIONAL_SLA
- ADMIN_ACTION_ATTEMPT
- operational workbench views

## Safety decisions

- No arbitrary `set status` endpoint.
- Paid orders cannot have commercial order-line amendments.
- Fulfilment-started lines cannot be edited through the line-amend endpoint.
- Shipped orders cannot use the normal cancellation path.
- Inventory move only supports an unallocated inventory row and preserves the row.
- Refund request is written internally before calling Stripe.
- Every dangerous feature has its own permission.
- 0.3.13 tag is not touched.

## One-shot workflow

1. Create/switch to a 0.3.14 branch.
2. Run `scripts/install_backend_megapack.ps1`.
3. Run `scripts/validate_0.3.14.ps1`.
4. Send back the single generated `dynetic-0.3.14-validation-*.txt`.
5. We fix the collected failures as one batch, then rerun the whole suite.

Do not deploy this package to PROD before the validation report is green and a
fresh-bootstrap / exact-baseline rehearsal has been completed.
