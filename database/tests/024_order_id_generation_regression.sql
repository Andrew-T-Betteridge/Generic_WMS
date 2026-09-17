\set ON_ERROR_STOP on

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

    IF v_definition !~* 'gen_random_uuid\s*\(\s*\)' THEN
        RAISE EXCEPTION
            'FAIL: PROCESS_ORDER_INTERFACE is not independently generating ORDER_ID';
    END IF;

    IF v_definition !~* '''WEB-''\s*\|\|' THEN
        RAISE EXCEPTION
            'FAIL: generated website ORDER_ID does not use WEB- prefix';
    END IF;

    RAISE NOTICE
        'PASS: website ORDER_ID is independent from the full idempotency/source order ID';
END
$$;
