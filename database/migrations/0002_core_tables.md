# Migration 0002 - Core WMS Tables

Generated from the previously refined KEEP + ADD specification.

Build order:
1. SKU
2. LOCATION
3. ADDRESS
4. INVENTORY
5. ORDER_HEADER
6. ORDER_LINE
7. INVENTORY_TRANSACTION
8. SHIPPING_MANIFEST

The SQL deliberately uses conservative constraints. Behavioural tables such as
allocation, kitting, interfaces, merge and carrier-selection will be added from
the existing WMS definitions/code rather than guessed.
