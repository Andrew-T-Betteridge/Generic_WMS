# Generic WMS Allocation V1

## Scope

Allocation V1 is deliberately small and generic. It reserves physical inventory
against order-line demand and records exactly which stock records supply which
demand.

It does not create pick tasks, decrement physical stock, book carriers or
manufacture inventory transactions for a reservation.

## Core meaning

| Object | Meaning |
|---|---|
| `INVENTORY.QTY_ON_HAND` | Physical stock held |
| `INVENTORY.QTY_ALLOCATED` | Quantity currently reserved |
| `INVENTORY_AVAILABILITY.QTY_AVAILABLE` | On hand minus reserved |
| `ORDER_LINE.QTY_SOFT_ALLOCATED` | Total reservation against the order line |
| `ALLOCATION` | Exact demand-to-inventory reservation relationship |

## Why ALLOCATION exists

An order line requiring 10 units may be fulfilled by several inventory records.
Totals on ORDER_LINE and INVENTORY cannot tell a picker, cancellation process or
support user which exact stock was reserved.

`core.ALLOCATION` therefore has a distinct purpose and a genuine one-to-many
lifecycle. It is not a legacy-copy table.

## V1 eligibility

Inventory must:

1. match client and SKU;
2. have `QTY_ON_HAND - QTY_ALLOCATED > 0`;
3. not have `DISALLOW_ALLOC = Y`;
4. not be in common locked/held/quarantine states;
5. sit in an active, allocatable, unlocked location;
6. match order-line batch, condition and owner where those values are supplied.

## Ranking

FIFO:

1. oldest `RECEIPT_DSTAMP`;
2. lowest `INVENTORY.KEY` as deterministic tie-break.

Future `config.ALLOCATION_RULE` / `ALLOCATION_RULE_CONDITION` can alter ranking
and eligibility without replacing the reservation data model.

## Concurrency

Inventory rows are locked using:

`FOR UPDATE OF i SKIP LOCKED`

This prevents two concurrent allocators from reserving the same available
quantity.

## Idempotency

`ALLOCATE_ORDER` only allocates:

`QTY_ORDERED - QTY_SOFT_ALLOCATED`

Calling it again on a fully allocated order returns `ALREADY_ALLOCATED` and does
not duplicate reservations.

## Deallocation

`DEALLOCATE_ORDER`:

- finds the order's `core.ALLOCATION` rows;
- subtracts each reservation from `INVENTORY.QTY_ALLOCATED`;
- deletes the reservation links;
- resets `ORDER_LINE.QTY_SOFT_ALLOCATED`.

This gives us the basis for cancellation and future reallocation.

## Inventory transactions

Allocation is a reservation, not a physical movement. Therefore V1 does not
write `INVENTORY_TRANSACTION`.

Future receive, adjust, pick and ship processes should write inventory
transactions when physical stock changes.

## Automated tests

`002_order_allocation_smoke_test.sql` proves:

- interface import;
- FIFO across two inventory records;
- exact allocation provenance;
- no QTY_ON_HAND reduction;
- repeated allocation does not duplicate reservations;
- deallocation releases stock.

`003_allocation_edge_cases.sql` proves:

- partial allocation;
- back-order flag;
- locked-location exclusion;
- no-stock behaviour.
