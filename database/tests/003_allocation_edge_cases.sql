\set ON_ERROR_STOP on

-- DYNETIC_TEST_ENVIRONMENT_GUARD_BEGIN
DO $dynetic_test_guard$
DECLARE
    v_database text := current_database();
BEGIN
    IF v_database NOT IN ('fulfilment_dev', 'fulfilment_test') THEN
        RAISE EXCEPTION
            'SAFETY STOP: database test execution is forbidden against database "%". Only fulfilment_dev and fulfilment_test are allowed.',
            v_database;
    END IF;

    RAISE NOTICE 'SAFETY: test database verified as %', v_database;
END
$dynetic_test_guard$;
-- DYNETIC_TEST_ENVIRONMENT_GUARD_END
BEGIN;

-- ============================================================
-- Allocation Edge Case Tests
--
-- Proves:
--   * partial allocation
--   * no-stock result
--   * locked/disallowed stock exclusion
-- ============================================================

INSERT INTO core.CLIENT (CLIENT_ID, DESCRIPTION, ACTIVE)
VALUES ('ALLOCEDGE', 'Allocation Edge Test Client', true)
ON CONFLICT (CLIENT_ID) DO NOTHING;

INSERT INTO core.SKU (
    CLIENT_ID, SKU_ID, DESCRIPTION,
    WEB_ACTIVE, WEB_FEATURED,
    SUPPLIER_DIRECT_ENABLED, AFFILIATE_FALLBACK, COMING_SOON
)
VALUES (
    'ALLOCEDGE', 'EDGE-SKU-001', 'Allocation edge SKU',
    'N', 'N', 'N', 'N', 'N'
)
ON CONFLICT (CLIENT_ID, SKU_ID) DO NOTHING;

INSERT INTO core.LOCATION (
    LOCATION_ID, LOC_TYPE, LOCK_STATUS, VOLUME,
    COUNT_NEEDED, ID, DESCRIPTION, ACTIVE,
    LIVESTOCK_ALLOWED, DISALLOW_ALLOC
)
VALUES
('EDGE-LOC-OK', 'STORAGE', 'UNLOCKED', 100, 'N', 910001, 'Edge usable', 'Y', 'Y', 'N'),
('EDGE-LOC-LOCK', 'STORAGE', 'LOCKED', 100, 'N', 910002, 'Edge locked', 'Y', 'Y', 'N')
ON CONFLICT (LOCATION_ID) DO NOTHING;

-- Only 2 allocatable units.
INSERT INTO core.INVENTORY (
    CLIENT_ID, SKU_ID, LOCATION_ID,
    QTY_ON_HAND, QTY_ALLOCATED, LOCK_STATUS,
    RECEIPT_DSTAMP, MOVE_DSTAMP, DISALLOW_ALLOC, DESCRIPTION
)
VALUES
('ALLOCEDGE', 'EDGE-SKU-001', 'EDGE-LOC-OK', 2, 0, 'UNLOCKED', now()-interval '2 days', now(), 'N', 'Usable edge stock'),
('ALLOCEDGE', 'EDGE-SKU-001', 'EDGE-LOC-LOCK', 50, 0, 'UNLOCKED', now()-interval '20 days', now(), 'N', 'Locked-location stock');

INSERT INTO interface.ORDER_HEADER_IF (
    CLIENT_ID, SOURCE_SYSTEM, SOURCE_ORDER_ID, ORDER_ID,
    CUSTOMER_ID, ORDER_DATE, ORDER_VALUE, CURRENCY
)
VALUES (
    'ALLOCEDGE', 'ALLOC_EDGE', 'EDGE-EXT-001', 'EDGE-ORDER-001',
    'EDGE-CUST', now(), 50, 'GBP'
)
RETURNING INTERFACE_ID \gset

INSERT INTO interface.ORDER_LINE_IF (
    INTERFACE_ID, LINE_ID, SKU_ID, QTY_ORDERED, PRODUCT_PRICE
)
VALUES (
    :'interface_id'::uuid, 1, 'EDGE-SKU-001', 5, 10
);

SELECT * FROM interface.PROCESS_ORDER_INTERFACE(:'interface_id'::uuid);
SELECT * FROM core.ALLOCATE_ORDER('ALLOCEDGE', 'EDGE-ORDER-001');

DO $$
DECLARE
    v_alloc NUMERIC;
    v_back VARCHAR;
    v_locked_alloc NUMERIC;
BEGIN
    SELECT COALESCE(QTY_SOFT_ALLOCATED, 0), BACK_ORDERED
    INTO v_alloc, v_back
    FROM core.ORDER_LINE
    WHERE CLIENT_ID = 'ALLOCEDGE'
      AND ORDER_ID = 'EDGE-ORDER-001'
      AND LINE_ID = 1;

    IF v_alloc <> 2 OR v_back <> 'Y' THEN
        RAISE EXCEPTION
            'Edge test failed: expected partial allocation 2 with back order Y, got % / %',
            v_alloc, v_back;
    END IF;

    SELECT QTY_ALLOCATED
    INTO v_locked_alloc
    FROM core.INVENTORY
    WHERE CLIENT_ID = 'ALLOCEDGE'
      AND DESCRIPTION = 'Locked-location stock';

    IF v_locked_alloc <> 0 THEN
        RAISE EXCEPTION
            'Edge test failed: stock in locked location was allocated';
    END IF;
END
$$;

-- A second order sees no remaining allocatable stock.
INSERT INTO interface.ORDER_HEADER_IF (
    CLIENT_ID, SOURCE_SYSTEM, SOURCE_ORDER_ID, ORDER_ID,
    CUSTOMER_ID, ORDER_DATE, ORDER_VALUE, CURRENCY
)
VALUES (
    'ALLOCEDGE', 'ALLOC_EDGE', 'EDGE-EXT-002', 'EDGE-ORDER-002',
    'EDGE-CUST', now(), 10, 'GBP'
)
RETURNING INTERFACE_ID \gset

INSERT INTO interface.ORDER_LINE_IF (
    INTERFACE_ID, LINE_ID, SKU_ID, QTY_ORDERED, PRODUCT_PRICE
)
VALUES (
    :'interface_id'::uuid, 1, 'EDGE-SKU-001', 1, 10
);

SELECT * FROM interface.PROCESS_ORDER_INTERFACE(:'interface_id'::uuid);
SELECT * FROM core.ALLOCATE_ORDER('ALLOCEDGE', 'EDGE-ORDER-002');

DO $$
DECLARE
    v_alloc NUMERIC;
BEGIN
    SELECT COALESCE(QTY_SOFT_ALLOCATED, 0)
    INTO v_alloc
    FROM core.ORDER_LINE
    WHERE CLIENT_ID = 'ALLOCEDGE'
      AND ORDER_ID = 'EDGE-ORDER-002'
      AND LINE_ID = 1;

    IF v_alloc <> 0 THEN
        RAISE EXCEPTION
            'Edge test failed: expected no stock allocation, got %',
            v_alloc;
    END IF;
END
$$;

ROLLBACK;

\echo 'Allocation edge-case tests passed.'
