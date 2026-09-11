# Warehouse Execution V1

## Purpose
Completes the first executable outbound lifecycle without reproducing legacy Dispatcher complexity.

`ORDER -> ALLOCATION -> PICK_TASK -> PICK -> ORDER_CONTAINER -> SHIPPING_MANIFEST -> SHIP`

## Quantity ownership
- Allocation: `INVENTORY.QTY_ALLOCATED` increases; physical `QTY_ON_HAND` is unchanged.
- Pick confirmation: `QTY_ON_HAND` and `QTY_ALLOCATED` both decrease; `ORDER_LINE.QTY_PICKED` increases.
- Shipment: `ORDER_LINE.QTY_SHIPPED` increases. Inventory is **not** reduced again.
- Short pick: the physically picked amount is consumed and the unpicked reservation is released for reallocation.

## Why PICK_TASK exists
It has a distinct operational lifecycle and answers only the execution questions: order, line, SKU, source inventory, location, required quantity, picked quantity and state. It is deliberately much smaller than a legacy WMS task subsystem.

## Allocation history
Allocation rows are no longer deleted. `QTY_PICKED`, `QTY_RELEASED` and `STATUS` preserve what happened. Open reserved quantity is:

`QTY_ALLOCATED - QTY_PICKED - QTY_RELEASED`

## Packing
No extra container-line table was added. `ORDER_CONTAINER` is the header and `SHIPPING_MANIFEST` is the line/content record. `PICK_TASK_ID` gives provenance from packed stock back to the exact pick.

## Inventory transactions
Only real physical inventory changes are written to `INVENTORY_TRANSACTION`. V1 therefore writes `PICK`; shipment does not write a zero-quantity fake stock movement.

## V1 functions
- `core.ALLOCATE_ORDER`
- `core.DEALLOCATE_ORDER`
- `core.CREATE_PICK_TASKS`
- `core.CONFIRM_PICK`
- `core.PACK_ORDER`
- `core.SHIP_CONTAINER`

## Operational views
- `core.PICK_WORK_QUEUE`
- `core.ORDER_FULFILMENT_WORKBENCH`
- `core.INVENTORY_RESERVATION_RECONCILIATION`
- `core.SHIPMENT_WORK_QUEUE`

## Deliberately deferred
Wave planning, replenishment, pick-path optimisation, cartonisation algorithms, multi-step task routing, carrier selection rules and merge rules remain later phases.
