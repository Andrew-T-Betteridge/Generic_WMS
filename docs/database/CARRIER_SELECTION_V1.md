# Carrier Selection V1

## Goal

Select an eligible carrier service for a packed order container without
hard-coding any particular retailer, product type or courier into the WMS core.

## Selection model

1. Read the packed `core.ORDER_CONTAINER`.
2. Read order destination/value requirements.
3. Calculate/derive weight and volume.
4. Reject services that violate hard limits.
5. For `DELIVERY_CLASS = LIVESTOCK`, reject services where
   `LIVE_GOODS_ALLOWED = false`.
6. Apply configured carrier selection rules.
7. Calculate estimated commercial cost from the best matching
   `CARRIER_SERVICE_RATE`; otherwise use service base/per-kg cost.
8. Rank using `CHEAPEST` (default) or `PRIORITY`.
9. Store the decision on `ORDER_CONTAINER` and open `SHIPPING_MANIFEST` rows.
10. Log the decision in `audit.RULE_DECISION_LOG`.

## Important design choice

Rules never contain SQL. Conditions are restricted to known fields and known
operators. This preserves the useful legacy WMS concept of configurable carrier
selection without copying its dynamic SQL / pseudo-column architecture.

## Supported safe condition fields

- WEIGHT_KG
- VOLUME_CM3
- ORDER_VALUE
- DELIVERY_CLASS
- DISPATCH_METHOD
- SERVICE_LEVEL
- COUNTRY
- POSTCODE
- POSTCODE_PREFIX
- FREE_DELIVERY

## Supported operators

EQ, NE, GT, GTE, LT, LTE, BETWEEN, IN, STARTS_WITH, IS_TRUE, IS_FALSE.

## Manual override

`core.OVERRIDE_CARRIER(...)` requires a reason and records the decision in the
rule decision log.

## Future

Carrier booking/API calls remain a separate later integration concern. Carrier
Selection V1 chooses the service; it does not send a booking to Evri, APC, DX,
Royal Mail or any other external provider.
