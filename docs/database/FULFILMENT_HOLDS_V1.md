# Fulfilment Holds V1

## Delivery class control

Carrier despatch restrictions are stored in:

`config.DELIVERY_CLASS_CONTROL`

This is intentionally separate from general application feature flags.

Key fields:

- CLIENT_ID
- DELIVERY_CLASS
- CARRIER_DESPATCH_ENABLED
- HOLD_REASON

Example:

```text
CLIENT_ID     FINATICS
DELIVERY_CLASS LIVESTOCK
CARRIER_DESPATCH_ENABLED false
```

That stops carrier despatch of LIVESTOCK containers only.

It does not stop:

- customer order creation
- allocation
- picking
- packing
- standard/non-live carrier despatch
- collection
- local delivery
- route delivery

## Customer mixed-order preference

`ORDER_HEADER.FULFILMENT_PREFERENCE`

- CONSOLIDATE
- SPLIT_WHEN_REQUIRED

## Future weather integration

Weather automation should update/evaluate delivery-class policy or apply a
WEATHER_HOLD using the same container hold framework. No temperature limits are
hard-coded in V1.
