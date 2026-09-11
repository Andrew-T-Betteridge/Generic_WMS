# Merge / Consolidation V1

## Scope

V1 consolidates two containers belonging to the same customer order.

It intentionally does not merge across orders because `ORDER_CONTAINER`
currently belongs to one `ORDER_ID`. Cross-order shipment consolidation should
only be introduced with a proper shipment/group entity rather than weakening
the current data model.

## Hard safety rules

A merge is rejected before configurable rules when:

- the containers belong to different orders;
- either container is SHIPPED, MERGED or CANCELLED;
- either container has shipped quantity;
- fulfilment methods differ;
- one container is held while the other is releasable;
- both already have different carriers;
- both already have different service levels.

## Safe default

Without an explicit merge rule, same-order containers are allowed to merge only
when their delivery class is the same.

Different delivery classes require an explicit ALLOW rule.

This is important for mixed orders such as LIVESTOCK + STANDARD.

## Rules

`config.MERGE_RULE`

- ordered by PRIORITY
- ALLOW or DENY
- client specific

`config.MERGE_RULE_CONDITION`

Safe supported fields:

- SAME_ORDER
- SAME_CUSTOMER
- SAME_POSTCODE
- SAME_COUNTRY
- SAME_DELIVERY_CLASS
- LEFT_DELIVERY_CLASS
- RIGHT_DELIVERY_CLASS
- SAME_FULFILMENT_METHOD
- FULFILMENT_METHOD
- COMBINED_WEIGHT_KG
- COMBINED_VOLUME_CM3
- ANY_HELD
- BOTH_HELD
- FULFILMENT_PREFERENCE

Operators:

- EQ
- NE
- GT
- GTE
- LT
- LTE
- BETWEEN
- IN
- IS_TRUE
- IS_FALSE

No dynamic SQL is used.

## Executing a merge

`core.MERGE_CONTAINERS`

The target survives.

The source becomes:

`STATUS = MERGED`

and records:

- MERGED_INTO_CONTAINER_ID
- MERGED_DSTAMP
- MERGED_BY
- MERGE_RULE_ID

Unshipped `SHIPPING_MANIFEST` rows are moved to the target.

Target weight and volume are added together.

Carrier selection is deliberately cleared on the surviving container because
the combined parcel must be re-rated and re-selected.

Physical dimensions are not mathematically added. The surviving physical
package determines its actual dimensions.

## FINatics mixed-order behaviour

A held livestock container cannot merge with releasable non-live goods.

If the customer selected split fulfilment, the non-live portion remains free to
dispatch.

A client rule may explicitly allow mixed LIVESTOCK + STANDARD consolidation for
a compatible fulfilment method such as LOCAL_DELIVERY when the customer selected
CONSOLIDATE.
