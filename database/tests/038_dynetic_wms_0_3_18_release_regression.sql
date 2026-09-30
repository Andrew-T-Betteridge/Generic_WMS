-- DYNETIC WMS 0.3.18 release contract

DO $$
DECLARE
    v_version text;
    v_current integer;
BEGIN
    SELECT api.GET_SYSTEM_VERSION()->>'version'
      INTO v_version;

    IF v_version <> '0.3.18' THEN
        RAISE EXCEPTION 'FAIL: expected system version 0.3.18, got %', v_version;
    END IF;

    SELECT COUNT(*)
      INTO v_current
      FROM config.SYSTEM_VERSION
     WHERE PRODUCT_CODE='DYNETIC_WMS'
       AND IS_CURRENT=true;

    IF v_current <> 1 THEN
        RAISE EXCEPTION 'FAIL: expected exactly one current DYNETIC_WMS version, got %', v_current;
    END IF;

    IF to_regclass('config.client_site') IS NULL THEN
        RAISE EXCEPTION 'FAIL: config.CLIENT_SITE missing';
    END IF;

    IF to_regclass('core.order_number_sequence') IS NULL THEN
        RAISE EXCEPTION 'FAIL: core.ORDER_NUMBER_SEQUENCE missing';
    END IF;

    IF to_regprocedure('core.next_order_id(character varying)') IS NULL THEN
        RAISE EXCEPTION 'FAIL: core.NEXT_ORDER_ID(varchar) missing';
    END IF;

    IF NOT EXISTS (
        SELECT 1
          FROM information_schema.columns
         WHERE table_schema='core'
           AND table_name='return_case'
           AND column_name='operation_id'
    ) THEN
        RAISE EXCEPTION 'FAIL: RETURN_CASE.OPERATION_ID missing';
    END IF;

    RAISE NOTICE 'PASS: DYNETIC WMS 0.3.18 release contract validated';
END
$$;
