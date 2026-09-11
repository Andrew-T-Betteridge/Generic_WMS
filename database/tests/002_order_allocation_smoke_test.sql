\set ON_ERROR_STOP on

BEGIN;

-- ============================================================
-- Generic WMS Allocation Smoke Test
--
-- Proves:
--   * interface order import
--   * FIFO allocation across multiple inventory records
--   * exact core.ALLOCATION provenance
--   * QTY_ON_HAND remains physical stock
--   * QTY_ALLOCATED increases
--   * ORDER_LINE.QTY_SOFT_ALLOCATED updates
--   * repeat allocation is idempotent
--   * deallocation releases reservations
-- ============================================================

INSERT INTO core.CLIENT (
    CLIENT_ID,
    DESCRIPTION,
    ACTIVE
)
VALUES (
    'ALLOCTEST',
    'Allocation Smoke Test Client',
    true
)
ON CONFLICT (CLIENT_ID) DO NOTHING;

INSERT INTO core.SKU (
    CLIENT_ID,
    SKU_ID,
    DESCRIPTION,
    WEB_ACTIVE,
    WEB_FEATURED,
    SUPPLIER_DIRECT_ENABLED,
    AFFILIATE_FALLBACK,
    COMING_SOON
)
VALUES (
    'ALLOCTEST',
    'ALLOC-SKU-001',
    'Allocation smoke test SKU',
    'N',
    'N',
    'N',
    'N',
    'N'
)
ON CONFLICT (CLIENT_ID, SKU_ID) DO NOTHING;

INSERT INTO core.LOCATION (
    LOCATION_ID,
    LOC_TYPE,
    LOCK_STATUS,
    VOLUME,
    COUNT_NEEDED,
    ID,
    DESCRIPTION,
    ACTIVE,
    LIVESTOCK_ALLOWED,
    DISALLOW_ALLOC
)
VALUES
(
    'ALLOC-LOC-01',
    'STORAGE',
    'UNLOCKED',
    100,
    'N',
    900001,
    'Allocation test location 1',
    'Y',
    'Y',
    'N'
),
(
    'ALLOC-LOC-02',
    'STORAGE',
    'UNLOCKED',
    100,
    'N',
    900002,
    'Allocation test location 2',
    'Y',
    'Y',
    'N'
)
ON CONFLICT (LOCATION_ID) DO NOTHING;

-- Oldest stock: 3 units
INSERT INTO core.INVENTORY (
    CLIENT_ID,
    SKU_ID,
    LOCATION_ID,
    QTY_ON_HAND,
    QTY_ALLOCATED,
    LOCK_STATUS,
    RECEIPT_DSTAMP,
    MOVE_DSTAMP,
    DISALLOW_ALLOC,
    DESCRIPTION
)
VALUES (
    'ALLOCTEST',
    'ALLOC-SKU-001',
    'ALLOC-LOC-01',
    3,
    0,
    'UNLOCKED',
    now() - interval '10 days',
    now() - interval '10 days',
    'N',
    'Oldest FIFO stock'
)
RETURNING KEY \gset inv_old_

-- Newer stock: 10 units
INSERT INTO core.INVENTORY (
    CLIENT_ID,
    SKU_ID,
    LOCATION_ID,
    QTY_ON_HAND,
    QTY_ALLOCATED,
    LOCK_STATUS,
    RECEIPT_DSTAMP,
    MOVE_DSTAMP,
    DISALLOW_ALLOC,
    DESCRIPTION
)
VALUES (
    'ALLOCTEST',
    'ALLOC-SKU-001',
    'ALLOC-LOC-02',
    10,
    0,
    'UNLOCKED',
    now() - interval '1 day',
    now() - interval '1 day',
    'N',
    'Newer FIFO stock'
)
RETURNING KEY \gset inv_new_

-- Order requires 5, so FIFO should reserve 3 from old + 2 from new.
INSERT INTO interface.ORDER_HEADER_IF (
    CLIENT_ID,
    SOURCE_SYSTEM,
    SOURCE_ORDER_ID,
    ORDER_ID,
    CUSTOMER_ID,
    ORDER_DATE,
    ORDER_VALUE,
    CURRENCY
)
VALUES (
    'ALLOCTEST',
    'ALLOC_SMOKE',
    'ALLOC-EXT-001',
    'ALLOC-ORDER-001',
    'ALLOC-CUST',
    now(),
    50,
    'GBP'
)
RETURNING INTERFACE_ID \gset

INSERT INTO interface.ORDER_LINE_IF (
    INTERFACE_ID,
    LINE_ID,
    SKU_ID,
    QTY_ORDERED,
    PRODUCT_PRICE
)
VALUES (
    :'interface_id'::uuid,
    1,
    'ALLOC-SKU-001',
    5,
    10
);

SELECT *
FROM interface.PROCESS_ORDER_INTERFACE(:'interface_id'::uuid);

SELECT *
FROM core.ALLOCATE_ORDER('ALLOCTEST', 'ALLOC-ORDER-001');

DO $$
DECLARE
    v_order_alloc NUMERIC;
    v_alloc_count INTEGER;
BEGIN
    SELECT COALESCE(QTY_SOFT_ALLOCATED, 0)
    INTO v_order_alloc
    FROM core.ORDER_LINE
    WHERE CLIENT_ID = 'ALLOCTEST'
      AND ORDER_ID = 'ALLOC-ORDER-001'
      AND LINE_ID = 1;

    IF v_order_alloc <> 5 THEN
        RAISE EXCEPTION
            'Allocation smoke test failed: expected order-line allocation 5, got %',
            v_order_alloc;
    END IF;

    SELECT COUNT(*)
    INTO v_alloc_count
    FROM core.ALLOCATION
    WHERE CLIENT_ID = 'ALLOCTEST'
      AND ORDER_ID = 'ALLOC-ORDER-001'
      AND LINE_ID = 1;

    IF v_alloc_count <> 2 THEN
        RAISE EXCEPTION
            'Allocation smoke test failed: expected 2 allocation links, got %',
            v_alloc_count;
    END IF;
END
$$;

-- Validate exact FIFO quantities using the known descriptions rather than psql
-- variables inside DO blocks.
DO $$
DECLARE
    v_old_reserved NUMERIC;
    v_new_reserved NUMERIC;
    v_old_on_hand NUMERIC;
    v_new_on_hand NUMERIC;
BEGIN
    SELECT i.QTY_ALLOCATED, i.QTY_ON_HAND
    INTO v_old_reserved, v_old_on_hand
    FROM core.INVENTORY i
    WHERE i.CLIENT_ID = 'ALLOCTEST'
      AND i.SKU_ID = 'ALLOC-SKU-001'
      AND i.DESCRIPTION = 'Oldest FIFO stock';

    SELECT i.QTY_ALLOCATED, i.QTY_ON_HAND
    INTO v_new_reserved, v_new_on_hand
    FROM core.INVENTORY i
    WHERE i.CLIENT_ID = 'ALLOCTEST'
      AND i.SKU_ID = 'ALLOC-SKU-001'
      AND i.DESCRIPTION = 'Newer FIFO stock';

    IF v_old_reserved <> 3 THEN
        RAISE EXCEPTION
            'Allocation smoke test failed: oldest stock should reserve 3, got %',
            v_old_reserved;
    END IF;

    IF v_new_reserved <> 2 THEN
        RAISE EXCEPTION
            'Allocation smoke test failed: newer stock should reserve 2, got %',
            v_new_reserved;
    END IF;

    IF v_old_on_hand <> 3 OR v_new_on_hand <> 10 THEN
        RAISE EXCEPTION
            'Allocation smoke test failed: allocation changed physical QTY_ON_HAND';
    END IF;
END
$$;

-- Re-run: nothing additional must be reserved.
SELECT *
FROM core.ALLOCATE_ORDER('ALLOCTEST', 'ALLOC-ORDER-001');

DO $$
DECLARE
    v_total NUMERIC;
    v_count INTEGER;
BEGIN
    SELECT COALESCE(SUM(QTY_ALLOCATED), 0), COUNT(*)
    INTO v_total, v_count
    FROM core.ALLOCATION
    WHERE CLIENT_ID = 'ALLOCTEST'
      AND ORDER_ID = 'ALLOC-ORDER-001';

    IF v_total <> 5 OR v_count <> 2 THEN
        RAISE EXCEPTION
            'Allocation smoke test failed: repeated allocation duplicated reservations';
    END IF;
END
$$;

-- Deallocate and prove stock reservation is released while history is retained.
SELECT *
FROM core.DEALLOCATE_ORDER('ALLOCTEST', 'ALLOC-ORDER-001');

DO $$
DECLARE
    v_inventory_reserved NUMERIC;
    v_order_reserved NUMERIC;
    v_links INTEGER;
BEGIN
    SELECT COALESCE(SUM(QTY_ALLOCATED), 0)
    INTO v_inventory_reserved
    FROM core.INVENTORY
    WHERE CLIENT_ID = 'ALLOCTEST'
      AND SKU_ID = 'ALLOC-SKU-001';

    SELECT COALESCE(QTY_SOFT_ALLOCATED, 0)
    INTO v_order_reserved
    FROM core.ORDER_LINE
    WHERE CLIENT_ID = 'ALLOCTEST'
      AND ORDER_ID = 'ALLOC-ORDER-001'
      AND LINE_ID = 1;

    SELECT COUNT(*)
    INTO v_links
    FROM core.ALLOCATION
    WHERE CLIENT_ID = 'ALLOCTEST'
      AND ORDER_ID = 'ALLOC-ORDER-001';

    IF v_inventory_reserved <> 0 THEN
        RAISE EXCEPTION
            'Allocation smoke test failed: inventory reservation not released';
    END IF;

    IF v_order_reserved <> 0 THEN
        RAISE EXCEPTION
            'Allocation smoke test failed: order-line reservation not reset';
    END IF;

    IF v_links <> 2 THEN
        RAISE EXCEPTION
            'Allocation smoke test failed: allocation history should retain 2 links, got %', v_links;
    END IF;

    IF EXISTS (
        SELECT 1 FROM core.ALLOCATION
        WHERE CLIENT_ID='ALLOCTEST' AND ORDER_ID='ALLOC-ORDER-001'
          AND (QTY_ALLOCATED-QTY_PICKED-QTY_RELEASED) <> 0
    ) THEN
        RAISE EXCEPTION 'Allocation smoke test failed: released allocation still has open quantity';
    END IF;
END
$$;

ROLLBACK;

\echo 'Order allocation smoke test passed.'
