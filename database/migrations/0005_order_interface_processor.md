# Migration 0005 - First processing workflow

Adds:
- standard `interface` schema naming
- simplified interface tables
- `interface.PROCESS_ORDER_INTERFACE(uuid)`
- rollback-based smoke test
- clean-build verification script

The processor currently performs:
1. idempotency check
2. client validation
3. line validation
4. SKU validation
5. operational ORDER_HEADER creation
6. operational ORDER_LINE creation
7. interface status update
8. processing/error logging

Allocation is intentionally the next engine, not bundled into order import.
