\set ON_ERROR_STOP on
\pset pager off
BEGIN;

-- Seed catalogue.
\ir ../seeds/001_finatics_fry_tray.sql

-- Self-contained stock location.
INSERT INTO core.LOCATION (
    LOCATION_ID,LOC_TYPE,LOCK_STATUS,VOLUME,DISALLOW_ALLOC,
    COUNT_NEEDED,ID,DESCRIPTION,ACTIVE,LIVESTOCK_ALLOWED
)
VALUES (
    'WEB-TEST-LOC','STORAGE','UNLOCKED',1000000,'N',
    'N',991301,'Website API test stock','Y','Y'
)
ON CONFLICT (LOCATION_ID) DO NOTHING;

-- INVENTORY has operational mandatory fields as well as quantity/location.
-- Keep this fixture representative of a real usable stock row.
INSERT INTO core.INVENTORY (
    CLIENT_ID,
    SKU_ID,
    SITE_ID,
    LOCATION_ID,
    QTY_ON_HAND,
    QTY_ALLOCATED,
    LOCK_STATUS,
    RECEIPT_DSTAMP,
    MOVE_DSTAMP,
    DISALLOW_ALLOC
)
VALUES (
    'FINATICS',
    'FRYTRAY001-S-G-W-G',
    'WEB',
    'WEB-TEST-LOC',
    5,
    0,
    'UNLOCKED',
    now(),
    now(),
    'N'
);

DO $$
DECLARE
    v JSONB;
BEGIN
    SELECT api.VALIDATE_BASKET(
        'FINATICS',
        '[{"sku_id":"FRYTRAY001-S-G-W-G","qty":2}]'::jsonb
    ) INTO v;

    IF NOT COALESCE((v->>'valid')::BOOLEAN,FALSE) THEN
        RAISE EXCEPTION 'Expected basket to validate: %',v;
    END IF;

    IF (v->>'subtotal')::NUMERIC <> 53.98 THEN
        RAISE EXCEPTION 'Unexpected basket subtotal: %',v->>'subtotal';
    END IF;
END
$$;

DO $$
DECLARE
    v JSONB;
BEGIN
    SELECT api.QUOTE_CHECKOUT(
        'FINATICS',
        '{
          "items":[{"sku_id":"FRYTRAY001-S-G-W-G","qty":2}],
          "deliveryAddress":{"postcode":"CV13 0AA","country":"GB"}
        }'::jsonb
    ) INTO v;

    IF NOT COALESCE((v->>'valid')::BOOLEAN,FALSE) THEN
        RAISE EXCEPTION 'Checkout quote should be valid: %',v;
    END IF;

    IF jsonb_array_length(v->'fulfilmentOptions') < 2 THEN
        RAISE EXCEPTION 'Expected multiple fulfilment options: %',v;
    END IF;
END
$$;

DO $$
DECLARE
    v JSONB;
    v_order_id TEXT;
BEGIN
    SELECT api.SUBMIT_WEB_ORDER(
        'FINATICS',
        '{
          "idempotencyKey":"WEBTEST-001",
          "items":[{"sku_id":"FRYTRAY001-S-G-W-G","qty":2}],
          "customer":{
            "name":"Website Test",
            "email":"website-test@example.invalid",
            "mobile":"07000000000"
          },
          "deliveryAddress":{
            "name":"Website Test",
            "address1":"1 Test Street",
            "town":"Hinckley",
            "county":"Leicestershire",
            "postcode":"CV13 0AA",
            "country":"GB"
          },
          "fulfilmentMethod":"CARRIER",
          "fulfilmentPreference":"CONSOLIDATE"
        }'::jsonb
    ) INTO v;

    IF v->>'status' <> 'ACCEPTED' THEN
        RAISE EXCEPTION 'Order submission failed: %',v;
    END IF;

    v_order_id := v->>'orderId';

    IF NOT EXISTS (
        SELECT 1
        FROM core.ORDER_HEADER
        WHERE CLIENT_ID='FINATICS'
          AND ORDER_ID=v_order_id
          AND POSTCODE='CV13 0AA'
          AND FULFILMENT_PREFERENCE='CONSOLIDATE'
          AND PAYMENT_STATUS='PENDING'
    ) THEN
        RAISE EXCEPTION 'Operational order not populated as expected.';
    END IF;

    IF NOT EXISTS (
        SELECT 1
        FROM interface.ORDER_HEADER_IF
        WHERE CLIENT_ID='FINATICS'
          AND SOURCE_SYSTEM='WEBSITE'
          AND SOURCE_ORDER_ID='WEBTEST-001'
          AND PROCESS_STATUS='PROCESSED'
    ) THEN
        RAISE EXCEPTION 'Website order did not pass through interface layer.';
    END IF;

    -- Retry proves API idempotency.
    SELECT api.SUBMIT_WEB_ORDER(
        'FINATICS',
        '{
          "idempotencyKey":"WEBTEST-001",
          "items":[{"sku_id":"FRYTRAY001-S-G-W-G","qty":2}],
          "customer":{"name":"Website Test","email":"website-test@example.invalid"},
          "deliveryAddress":{
            "name":"Website Test",
            "address1":"1 Test Street",
            "town":"Hinckley",
            "postcode":"CV13 0AA",
            "country":"GB"
          },
          "fulfilmentMethod":"CARRIER",
          "fulfilmentPreference":"CONSOLIDATE"
        }'::jsonb
    ) INTO v;

    IF NOT COALESCE((v->>'idempotentReplay')::BOOLEAN,FALSE) THEN
        RAISE EXCEPTION 'Expected idempotent replay: %',v;
    END IF;

    SELECT api.GET_ORDER_STATUS('FINATICS',v_order_id) INTO v;

    IF v IS NULL OR v->>'orderId'<>v_order_id THEN
        RAISE EXCEPTION 'Order status API failed.';
    END IF;
END
$$;

ROLLBACK;
