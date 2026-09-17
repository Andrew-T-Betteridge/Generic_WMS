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

INSERT INTO core.CLIENT (CLIENT_ID,DESCRIPTION,ACTIVE)
VALUES ('HOLDTEST','Hold Test',TRUE)
ON CONFLICT (CLIENT_ID) DO NOTHING;

INSERT INTO config.DELIVERY_CLASS_CONTROL (
    CLIENT_ID,DELIVERY_CLASS,CARRIER_DESPATCH_ENABLED,HOLD_REASON
)
VALUES (
    'HOLDTEST','LIVESTOCK',FALSE,
    'Livestock carrier despatch disabled for test.'
)
ON CONFLICT (CLIENT_ID,DELIVERY_CLASS)
DO UPDATE SET
    CARRIER_DESPATCH_ENABLED=EXCLUDED.CARRIER_DESPATCH_ENABLED,
    HOLD_REASON=EXCLUDED.HOLD_REASON,
    LAST_UPDATE_DSTAMP=now();

INSERT INTO core.ORDER_HEADER (
    CLIENT_ID,ORDER_ID,ORDER_DATE,ORDER_VALUE,INV_CURRENCY,
    FREE_DELIVERY,FULFILMENT_PREFERENCE
)
VALUES (
    'HOLDTEST','HOLD-ORDER-1',now(),50,'GBP','N','SPLIT_WHEN_REQUIRED'
);

INSERT INTO core.ORDER_CONTAINER (
    CLIENT_ID,ORDER_ID,CONTAINER_ID,STATUS,DELIVERY_CLASS,FULFILMENT_METHOD
)
VALUES
    ('HOLDTEST','HOLD-ORDER-1','HOLD-FISH','PACKED','LIVESTOCK','CARRIER'),
    ('HOLDTEST','HOLD-ORDER-1','HOLD-DRY','PACKED','STANDARD','CARRIER');

SELECT * FROM core.EVALUATE_DELIVERY_HOLD('HOLDTEST','HOLD-FISH','TEST');
SELECT * FROM core.EVALUATE_DELIVERY_HOLD('HOLDTEST','HOLD-DRY','TEST');

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM core.ORDER_CONTAINER
        WHERE CLIENT_ID='HOLDTEST'
          AND CONTAINER_ID='HOLD-FISH'
          AND HOLD_STATUS='DELIVERY_HOLD'
          AND HOLD_SOURCE='DELIVERY_CLASS_CONTROL'
    ) THEN
        RAISE EXCEPTION 'Livestock carrier container should be held.';
    END IF;

    IF NOT EXISTS (
        SELECT 1
        FROM core.ORDER_CONTAINER
        WHERE CLIENT_ID='HOLDTEST'
          AND CONTAINER_ID='HOLD-DRY'
          AND HOLD_STATUS='NONE'
    ) THEN
        RAISE EXCEPTION 'Non-live container must remain releasable.';
    END IF;

    IF NOT EXISTS (
        SELECT 1
        FROM core.MIXED_ORDER_FULFILMENT_WORKBENCH
        WHERE CLIENT_ID='HOLDTEST'
          AND ORDER_ID='HOLD-ORDER-1'
          AND RECOMMENDED_ACTION='RELEASE_NON_LIVE'
    ) THEN
        RAISE EXCEPTION
            'Split mixed order should recommend releasing non-live goods.';
    END IF;
END
$$;

-- Changing livestock to local delivery bypasses carrier-only restriction.
SELECT * FROM core.SET_CONTAINER_FULFILMENT(
    'HOLDTEST','HOLD-FISH','LOCAL_DELIVERY','TEST'
);

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM core.ORDER_CONTAINER
        WHERE CLIENT_ID='HOLDTEST'
          AND CONTAINER_ID='HOLD-FISH'
          AND FULFILMENT_METHOD='LOCAL_DELIVERY'
          AND HOLD_STATUS='NONE'
    ) THEN
        RAISE EXCEPTION
            'Local livestock delivery should not remain carrier-held.';
    END IF;
END
$$;

ROLLBACK;
