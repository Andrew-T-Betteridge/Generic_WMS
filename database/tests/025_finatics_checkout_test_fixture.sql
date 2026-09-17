-- TEST-only checkout matrix fixture for FINATICS.
-- Intended for fulfilment_test only.
--
-- Creates:
--   - WEB-E2E-LOC (livestock-enabled test location)
--   - 20 units of FRYTRAY001-S-G-W-G
--   - TEST-LIVESTOCK-001 / TEST-LIVESTOCK-001-4CM
--   - 5 units of livestock stock
--
-- Prerequisite:
--   database/seeds/001_finatics_fry_tray.sql

\set ON_ERROR_STOP on
\pset pager off

DO $$
BEGIN
    IF current_database() <> 'fulfilment_test' THEN
        RAISE EXCEPTION
            'SAFETY STOP: this fixture is for fulfilment_test only. Current database: %',
            current_database();
    END IF;
END
$$;

--------------------------------------------------------------------------
-- TEST LOCATION
--
-- core.LOCATION has these mandatory fields in fulfilment_test:
-- LOCATION_ID, LOC_TYPE, LOCK_STATUS, VOLUME, COUNT_NEEDED,
-- ID, ACTIVE, LIVESTOCK_ALLOWED.
--------------------------------------------------------------------------
INSERT INTO core.LOCATION (
    SITE_ID,
    LOCATION_ID,
    LOC_TYPE,
    LOCK_STATUS,
    VOLUME,
    DISALLOW_ALLOC,
    COUNT_NEEDED,
    ID,
    DESCRIPTION,
    ACTIVE,
    LIVESTOCK_ALLOWED
)
SELECT
    'WEB',
    'WEB-E2E-LOC',
    'STORAGE',
    'UNLOCKED',
    1000000,
    'N',
    'N',
    (SELECT COALESCE(MAX(ID),0)+1 FROM core.LOCATION),
    'Website checkout regression test location',
    'Y',
    'Y'
WHERE NOT EXISTS (
    SELECT 1
    FROM core.LOCATION
    WHERE LOCATION_ID='WEB-E2E-LOC'
);

UPDATE core.LOCATION
SET SITE_ID='WEB',
    LOC_TYPE='STORAGE',
    LOCK_STATUS='UNLOCKED',
    VOLUME=1000000,
    DISALLOW_ALLOC='N',
    COUNT_NEEDED='N',
    ACTIVE='Y',
    LIVESTOCK_ALLOWED='Y',
    DESCRIPTION='Website checkout regression test location'
WHERE LOCATION_ID='WEB-E2E-LOC';

--------------------------------------------------------------------------
-- STANDARD PRODUCT PREREQUISITE
--------------------------------------------------------------------------
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM core.SKU
        WHERE CLIENT_ID='FINATICS'
          AND SKU_ID='FRYTRAY001-S-G-W-G'
    ) THEN
        RAISE EXCEPTION
            'FRYTRAY001-S-G-W-G does not exist. Run database/seeds/001_finatics_fry_tray.sql first.';
    END IF;
END
$$;

--------------------------------------------------------------------------
-- DETERMINISTIC STANDARD STOCK
--------------------------------------------------------------------------
DELETE FROM core.INVENTORY
WHERE CLIENT_ID='FINATICS'
  AND SKU_ID='FRYTRAY001-S-G-W-G'
  AND LOCATION_ID='WEB-E2E-LOC';

INSERT INTO core.INVENTORY (
    "key",
    CLIENT_ID,
    SKU_ID,
    SITE_ID,
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
    (SELECT COALESCE(MAX("key"),0)+1 FROM core.INVENTORY),
    'FINATICS',
    'FRYTRAY001-S-G-W-G',
    'WEB',
    'WEB-E2E-LOC',
    20,
    0,
    'UNLOCKED',
    now(),
    now(),
    'N',
    'TEST standard checkout regression stock'
);

--------------------------------------------------------------------------
-- LIVESTOCK SKU MASTER
--------------------------------------------------------------------------
INSERT INTO core.SKU (
    CLIENT_ID,
    SKU_ID,
    DESCRIPTION,
    PRODUCT_GROUP,
    FAMILY_GROUP,
    CATEGORY,
    SELL_PRICE,
    WEB_TITLE,
    WEB_DESCRIPTION,
    WEB_SLUG,
    WEB_ACTIVE,
    WEB_FEATURED,
    FULFILMENT_TYPE,
    SUPPLIER_DIRECT_ENABLED,
    AFFILIATE_FALLBACK,
    MIN_ORDER_QTY,
    COMING_SOON,
    ECOMMERCE,
    OBSOLETE_PRODUCT,
    DECATALOGUED,
    CREATED_BY,
    CREATION_DATE,
    LAST_UPDATED_BY,
    LAST_UPDATE_DATE
)
SELECT
    'FINATICS',
    'TEST-LIVESTOCK-001-4CM',
    'TEST Malawi Livestock Fish - 4cm',
    'FISH',
    'MALAWI',
    'LIVESTOCK',
    12.99,
    'TEST Malawi Livestock Fish - 4cm',
    'Test-only livestock product for checkout regression.',
    'test-malawi-livestock-fish-4cm',
    'Y',
    'N',
    'LIVESTOCK',
    'N',
    'N',
    1,
    'N',
    'Y',
    'N',
    'N',
    'TEST_FIXTURE',
    now(),
    'TEST_FIXTURE',
    now()
WHERE NOT EXISTS (
    SELECT 1
    FROM core.SKU
    WHERE CLIENT_ID='FINATICS'
      AND SKU_ID='TEST-LIVESTOCK-001-4CM'
);

UPDATE core.SKU
SET DESCRIPTION='TEST Malawi Livestock Fish - 4cm',
    PRODUCT_GROUP='FISH',
    FAMILY_GROUP='MALAWI',
    CATEGORY='LIVESTOCK',
    SELL_PRICE=12.99,
    WEB_TITLE='TEST Malawi Livestock Fish - 4cm',
    WEB_DESCRIPTION='Test-only livestock product for checkout regression.',
    WEB_SLUG='test-malawi-livestock-fish-4cm',
    WEB_ACTIVE='Y',
    WEB_FEATURED='N',
    FULFILMENT_TYPE='LIVESTOCK',
    SUPPLIER_DIRECT_ENABLED='N',
    AFFILIATE_FALLBACK='N',
    MIN_ORDER_QTY=1,
    COMING_SOON='N',
    ECOMMERCE='Y',
    OBSOLETE_PRODUCT='N',
    DECATALOGUED='N',
    LAST_UPDATED_BY='TEST_FIXTURE',
    LAST_UPDATE_DATE=now()
WHERE CLIENT_ID='FINATICS'
  AND SKU_ID='TEST-LIVESTOCK-001-4CM';

--------------------------------------------------------------------------
-- LIVESTOCK WEB PRODUCT
--------------------------------------------------------------------------
INSERT INTO core.PRODUCT (
    CLIENT_ID,
    PRODUCT_ID,
    PRODUCT_NAME,
    SLUG,
    BRAND_NAME,
    SHORT_DESCRIPTION,
    DESCRIPTION,
    DELIVERY_CLASS,
    CURRENCY,
    MEDIA,
    SPECIFICATION,
    ACTIVE,
    FEATURED,
    SORT_SEQUENCE,
    CREATED_DSTAMP,
    LAST_UPDATE_DSTAMP,
    PRODUCT_TYPE,
    SEARCH_METADATA
)
SELECT
    'FINATICS',
    'TEST-LIVESTOCK-001',
    'TEST Malawi Livestock Fish',
    'test-malawi-livestock-fish',
    'FINatics Aquatics',
    'Test-only livestock item used for checkout regression.',
    'Test-only livestock product used to prove fish, mixed basket, delivery and stock allocation behaviour.',
    'LIVESTOCK',
    'GBP',
    '[]'::jsonb,
    '{"testFixture":true}'::jsonb,
    TRUE,
    FALSE,
    9999,
    now(),
    now(),
    'LIVESTOCK',
    '{"testFixture":true}'::jsonb
WHERE NOT EXISTS (
    SELECT 1
    FROM core.PRODUCT
    WHERE CLIENT_ID='FINATICS'
      AND PRODUCT_ID='TEST-LIVESTOCK-001'
);

UPDATE core.PRODUCT
SET PRODUCT_NAME='TEST Malawi Livestock Fish',
    SLUG='test-malawi-livestock-fish',
    BRAND_NAME='FINatics Aquatics',
    DELIVERY_CLASS='LIVESTOCK',
    CURRENCY='GBP',
    ACTIVE=TRUE,
    FEATURED=FALSE,
    PRODUCT_TYPE='LIVESTOCK',
    SPECIFICATION='{"testFixture":true}'::jsonb,
    SEARCH_METADATA='{"testFixture":true}'::jsonb,
    LAST_UPDATE_DSTAMP=now()
WHERE CLIENT_ID='FINATICS'
  AND PRODUCT_ID='TEST-LIVESTOCK-001';

--------------------------------------------------------------------------
-- LIVESTOCK WEB VARIANT
--------------------------------------------------------------------------
INSERT INTO core.PRODUCT_VARIANT (
    CLIENT_ID,
    PRODUCT_ID,
    SKU_ID,
    VARIANT_NAME,
    OPTION_VALUES,
    WEB_PRICE,
    ACTIVE,
    SORT_SEQUENCE,
    CREATED_DSTAMP,
    LAST_UPDATE_DSTAMP,
    SALE_TYPE,
    AVAILABILITY_STATE,
    WEB_METADATA,
    MIN_ORDER_QTY,
    MAX_ORDER_QTY,
    QTY_INCREMENT
)
SELECT
    'FINATICS',
    'TEST-LIVESTOCK-001',
    'TEST-LIVESTOCK-001-4CM',
    'Approx. 4 cm',
    '{"size":"Approx. 4 cm","testFixture":true}'::jsonb,
    12.99,
    TRUE,
    10,
    now(),
    now(),
    'STANDARD',
    'AVAILABLE',
    '{"testFixture":true}'::jsonb,
    1,
    10,
    1
WHERE NOT EXISTS (
    SELECT 1
    FROM core.PRODUCT_VARIANT
    WHERE CLIENT_ID='FINATICS'
      AND SKU_ID='TEST-LIVESTOCK-001-4CM'
);

UPDATE core.PRODUCT_VARIANT
SET PRODUCT_ID='TEST-LIVESTOCK-001',
    VARIANT_NAME='Approx. 4 cm',
    OPTION_VALUES='{"size":"Approx. 4 cm","testFixture":true}'::jsonb,
    WEB_PRICE=12.99,
    ACTIVE=TRUE,
    SALE_TYPE='STANDARD',
    AVAILABILITY_STATE='AVAILABLE',
    WEB_METADATA='{"testFixture":true}'::jsonb,
    MIN_ORDER_QTY=1,
    MAX_ORDER_QTY=10,
    QTY_INCREMENT=1,
    LAST_UPDATE_DSTAMP=now()
WHERE CLIENT_ID='FINATICS'
  AND SKU_ID='TEST-LIVESTOCK-001-4CM';

--------------------------------------------------------------------------
-- DETERMINISTIC LIVESTOCK STOCK
--------------------------------------------------------------------------
DELETE FROM core.INVENTORY
WHERE CLIENT_ID='FINATICS'
  AND SKU_ID='TEST-LIVESTOCK-001-4CM';

INSERT INTO core.INVENTORY (
    "key",
    CLIENT_ID,
    SKU_ID,
    SITE_ID,
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
    (SELECT COALESCE(MAX("key"),0)+1 FROM core.INVENTORY),
    'FINATICS',
    'TEST-LIVESTOCK-001-4CM',
    'WEB',
    'WEB-E2E-LOC',
    5,
    0,
    'UNLOCKED',
    now(),
    now(),
    'N',
    'TEST livestock checkout regression stock'
);

--------------------------------------------------------------------------
--------------------------------------------------------------------------
-- TEST LOCAL DELIVERY ZONE
--------------------------------------------------------------------------
INSERT INTO config.DELIVERY_ZONE (
    CLIENT_ID,
    ZONE_ID,
    ZONE_NAME,
    FULFILMENT_METHOD,
    COUNTRY,
    POSTCODE_PREFIX,
    MIN_ORDER_VALUE,
    DELIVERY_PRICE,
    CURRENCY,
    REQUIRES_MANUAL_CONFIRMATION,
    PRIORITY,
    ACTIVE
)
VALUES (
    'FINATICS',
    'LOCAL-CV13',
    'Local CV13 Delivery',
    'LOCAL_DELIVERY',
    'GB',
    'CV13',
    20,
    5,
    'GBP',
    FALSE,
    10,
    TRUE
)
ON CONFLICT (CLIENT_ID,ZONE_ID)
DO UPDATE SET
    ZONE_NAME=EXCLUDED.ZONE_NAME,
    FULFILMENT_METHOD=EXCLUDED.FULFILMENT_METHOD,
    COUNTRY=EXCLUDED.COUNTRY,
    POSTCODE_PREFIX=EXCLUDED.POSTCODE_PREFIX,
    MIN_ORDER_VALUE=EXCLUDED.MIN_ORDER_VALUE,
    DELIVERY_PRICE=EXCLUDED.DELIVERY_PRICE,
    CURRENCY=EXCLUDED.CURRENCY,
    REQUIRES_MANUAL_CONFIRMATION=EXCLUDED.REQUIRES_MANUAL_CONFIRMATION,
    PRIORITY=EXCLUDED.PRIORITY,
    ACTIVE=TRUE,
    LAST_UPDATE_DSTAMP=now();
-- FINAL FIXTURE CHECK
--------------------------------------------------------------------------
SELECT
    p.PRODUCT_ID,
    p.PRODUCT_NAME,
    p.DELIVERY_CLASS,
    pv.SKU_ID,
    pv.WEB_PRICE,
    pv.AVAILABILITY_STATE,
    COALESCE(SUM(i.QTY_ON_HAND),0) AS QTY_ON_HAND,
    COALESCE(SUM(i.QTY_ALLOCATED),0) AS QTY_ALLOCATED,
    COALESCE(SUM(i.QTY_ON_HAND-i.QTY_ALLOCATED),0) AS AVAILABLE_QTY
FROM core.PRODUCT p
JOIN core.PRODUCT_VARIANT pv
  ON pv.CLIENT_ID=p.CLIENT_ID
 AND pv.PRODUCT_ID=p.PRODUCT_ID
LEFT JOIN core.INVENTORY i
  ON i.CLIENT_ID=pv.CLIENT_ID
 AND i.SKU_ID=pv.SKU_ID
WHERE p.CLIENT_ID='FINATICS'
  AND pv.SKU_ID IN (
      'FRYTRAY001-S-G-W-G',
      'TEST-LIVESTOCK-001-4CM'
  )
GROUP BY
    p.PRODUCT_ID,
    p.PRODUCT_NAME,
    p.DELIVERY_CLASS,
    pv.SKU_ID,
    pv.WEB_PRICE,
    pv.AVAILABILITY_STATE
ORDER BY pv.SKU_ID;
