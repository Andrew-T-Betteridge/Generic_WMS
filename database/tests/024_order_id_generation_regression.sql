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

DO $$
DECLARE
    v_definition TEXT;
BEGIN
    SELECT pg_get_functiondef(
        'interface.process_order_interface(uuid)'::regprocedure
    )
    INTO v_definition;

    IF v_definition ~* 'left\s*\(\s*v_header\.source_order_id\s*,\s*20\s*\)' THEN
        RAISE EXCEPTION
            'FAIL: operational ORDER_ID is still derived by truncating SOURCE_ORDER_ID';
    END IF;

    IF v_definition !~* 'v_order_id\s*:=\s*core\.next_order_id\s*\(\s*v_header\.client_id\s*\)' THEN
        RAISE EXCEPTION
            'FAIL: PROCESS_ORDER_INTERFACE is not using the authoritative WMS NEXT_ORDER_ID allocator';
    END IF;

    IF v_definition ~* 'v_order_id\s*:=\s*coalesce'
       OR v_definition ~* 'nullif\s*\(\s*v_header\.order_id'
       OR v_definition ~* 'gen_random_uuid\s*\(' THEN
        RAISE EXCEPTION
            'FAIL: PROCESS_ORDER_INTERFACE contains a legacy external/random ORDER_ID allocation path';
    END IF;

    RAISE NOTICE
        'PASS: PROCESS_ORDER_INTERFACE uses authoritative WMS NEXT_ORDER_ID and does not derive operational ORDER_ID from source/interface IDs';
END
$$;
