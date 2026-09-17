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
VALUES ('PREFTEST','Preference Test',TRUE)
ON CONFLICT (CLIENT_ID) DO NOTHING;

INSERT INTO core.ORDER_HEADER (
    CLIENT_ID,ORDER_ID,ORDER_DATE,ORDER_VALUE,INV_CURRENCY,FREE_DELIVERY
) VALUES ('PREFTEST','PREF-ORDER-1',now(),20,'GBP','N');

SELECT * FROM core.SET_FULFILMENT_PREFERENCE(
    'PREFTEST','PREF-ORDER-1','CONSOLIDATE','TEST'
);

DO $$
BEGIN
    IF (SELECT FULFILMENT_PREFERENCE FROM core.ORDER_HEADER
        WHERE CLIENT_ID='PREFTEST' AND ORDER_ID='PREF-ORDER-1') <> 'CONSOLIDATE' THEN
        RAISE EXCEPTION 'CONSOLIDATE preference was not stored.';
    END IF;
END
$$;

DO $$
DECLARE v_status varchar;
BEGIN
    SELECT RESULT_STATUS INTO v_status
    FROM core.SET_FULFILMENT_PREFERENCE(
        'PREFTEST','PREF-ORDER-1','INVALID','TEST'
    );
    IF v_status <> 'ERROR' THEN
        RAISE EXCEPTION 'Invalid fulfilment preference should be rejected.';
    END IF;
END
$$;

ROLLBACK;
