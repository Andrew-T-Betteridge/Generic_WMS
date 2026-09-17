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
-- Generic WMS
-- Order Interface Smoke Test
--
-- Confirms that an external order can be:
--   1. Inserted into the interface
--   2. Processed
--   3. Created in operational order tables
--   4. Marked PROCESSED in the interface
--
-- Everything is rolled back after the test.
-- ============================================================


-- ------------------------------------------------------------
-- 1. Test client
-- ------------------------------------------------------------

INSERT INTO core.CLIENT (
    CLIENT_ID,
    DESCRIPTION,
    ACTIVE
)
VALUES (
    'TESTCLIENT',
    'Smoke Test Client',
    true
)
ON CONFLICT (CLIENT_ID) DO NOTHING;


-- ------------------------------------------------------------
-- 2. Test SKU
-- ------------------------------------------------------------

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
    'TESTCLIENT',
    'TEST-SKU-001',
    'Interface smoke test SKU',
    'N',
    'N',
    'N',
    'N',
    'N'
)
ON CONFLICT (CLIENT_ID, SKU_ID) DO NOTHING;


-- ------------------------------------------------------------
-- 3. Interface order header
-- ------------------------------------------------------------

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
    'TESTCLIENT',
    'SMOKE_TEST',
    'EXT-10001',
    'TEST-10001',
    'CUST-001',
    now(),
    19.99,
    'GBP'
)
RETURNING INTERFACE_ID \gset


-- ------------------------------------------------------------
-- 4. Interface order line
-- ------------------------------------------------------------

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
    'TEST-SKU-001',
    2,
    9.995
);


-- ------------------------------------------------------------
-- 5. Process order
-- ------------------------------------------------------------

SELECT *
FROM interface.PROCESS_ORDER_INTERFACE(
    :'interface_id'::uuid
);


-- ------------------------------------------------------------
-- 6. Validate operational ORDER_HEADER
-- ------------------------------------------------------------

DO $$
BEGIN

    IF NOT EXISTS (
        SELECT 1
        FROM core.ORDER_HEADER
        WHERE CLIENT_ID = 'TESTCLIENT'
          AND ORDER_ID = 'TEST-10001'
    ) THEN

        RAISE EXCEPTION
            'Smoke test failed: ORDER_HEADER was not created';

    END IF;

END
$$;


-- ------------------------------------------------------------
-- 7. Validate operational ORDER_LINE
-- ------------------------------------------------------------

DO $$
BEGIN

    IF NOT EXISTS (
        SELECT 1
        FROM core.ORDER_LINE
        WHERE CLIENT_ID = 'TESTCLIENT'
          AND ORDER_ID = 'TEST-10001'
          AND LINE_ID = 1
          AND QTY_ORDERED = 2
    ) THEN

        RAISE EXCEPTION
            'Smoke test failed: ORDER_LINE was not created';

    END IF;

END
$$;


-- ------------------------------------------------------------
-- 8. Validate interface header status
--
-- Use SOURCE_ORDER_ID rather than the psql interface_id
-- variable because psql variables are not expanded inside
-- PostgreSQL DO blocks.
-- ------------------------------------------------------------

DO $$
BEGIN

    IF NOT EXISTS (
        SELECT 1
        FROM interface.ORDER_HEADER_IF
        WHERE CLIENT_ID = 'TESTCLIENT'
          AND SOURCE_SYSTEM = 'SMOKE_TEST'
          AND SOURCE_ORDER_ID = 'EXT-10001'
          AND PROCESS_STATUS = 'PROCESSED'
    ) THEN

        RAISE EXCEPTION
            'Smoke test failed: ORDER_HEADER_IF was not marked PROCESSED';

    END IF;

END
$$;


-- ------------------------------------------------------------
-- 9. Validate interface line status
-- ------------------------------------------------------------

DO $$
BEGIN

    IF NOT EXISTS (
        SELECT 1
        FROM interface.ORDER_LINE_IF lif
        JOIN interface.ORDER_HEADER_IF hif
          ON hif.INTERFACE_ID = lif.INTERFACE_ID
        WHERE hif.CLIENT_ID = 'TESTCLIENT'
          AND hif.SOURCE_SYSTEM = 'SMOKE_TEST'
          AND hif.SOURCE_ORDER_ID = 'EXT-10001'
          AND lif.PROCESS_STATUS = 'PROCESSED'
    ) THEN

        RAISE EXCEPTION
            'Smoke test failed: ORDER_LINE_IF was not marked PROCESSED';

    END IF;

END
$$;


-- ------------------------------------------------------------
-- 10. Clean up
-- ------------------------------------------------------------

ROLLBACK;


\echo 'Order interface smoke test passed.'