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
\pset pager off
BEGIN;

DO $$
DECLARE
    v_count INTEGER;
    v_current INTEGER;
    v_info JSONB;
BEGIN
    SELECT COUNT(*)
      INTO v_count
      FROM config.SYSTEM_VERSION
     WHERE PRODUCT_CODE='DYNETIC_WMS'
       AND VERSION_NUMBER='0.3.12';

    IF v_count<>1 THEN
        RAISE EXCEPTION 'Expected DYNETIC WMS version 0.3.12 exactly once; got %.',v_count;
    END IF;

    SELECT COUNT(*)
      INTO v_current
      FROM config.SYSTEM_VERSION
     WHERE PRODUCT_CODE='DYNETIC_WMS'
       AND IS_CURRENT=TRUE;

    IF v_current<>1 THEN
        RAISE EXCEPTION 'Expected exactly one current DYNETIC WMS version; got %.',v_current;
    END IF;

    SELECT api.GET_SYSTEM_VERSION() INTO v_info;

    IF v_info->>'productName'<>'DYNETIC WMS' THEN
        RAISE EXCEPTION 'Unexpected product name: %',v_info;
    END IF;

    IF v_info->>'version'<>'0.3.12' THEN
        RAISE EXCEPTION 'Unexpected current version: %',v_info;
    END IF;

    IF (v_info->>'major')::INTEGER<>0
       OR (v_info->>'minor')::INTEGER<>3
       OR (v_info->>'patch')::INTEGER<>12 THEN
        RAISE EXCEPTION 'Unexpected semantic version components: %',v_info;
    END IF;

    IF v_info->>'releaseChannel'<>'RELEASE' THEN
        RAISE EXCEPTION 'Unexpected release channel: %',v_info;
    END IF;
END
$$;

ROLLBACK;
