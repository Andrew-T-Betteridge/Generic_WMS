\set ON_ERROR_STOP on

DO $dynetic_test_guard$
DECLARE
    v_database text := current_database();
BEGIN
    IF v_database NOT IN ('fulfilment_dev', 'fulfilment_test') THEN
        RAISE EXCEPTION
            'SAFETY STOP: admin operations control-plane regression may only run against fulfilment_dev or fulfilment_test; current database is "%".',
            v_database;
    END IF;
    RAISE NOTICE 'SAFETY: admin operations control-plane regression verified database %', v_database;
END
$dynetic_test_guard$;

BEGIN;

DO $test$
DECLARE
    v_version text;
    v_config_version text;
    v_current integer;
    v_missing_owner integer;
    v_permission_count integer;
    v_reason_count integer;
BEGIN
    SELECT api.GET_SYSTEM_VERSION()->>'version'
      INTO v_version;

    IF NULLIF(btrim(v_version),'') IS NULL THEN
        RAISE EXCEPTION 'GET_SYSTEM_VERSION returned no current DYNETIC WMS version';
    END IF;

    SELECT count(*), max(VERSION_NUMBER)
      INTO v_current, v_config_version
      FROM config.SYSTEM_VERSION
     WHERE PRODUCT_CODE='DYNETIC_WMS'
       AND IS_CURRENT=true;

    IF v_current <> 1 THEN
        RAISE EXCEPTION 'Expected exactly one current DYNETIC version, got %', v_current;
    END IF;

    IF v_config_version IS DISTINCT FROM v_version THEN
        RAISE EXCEPTION
            'GET_SYSTEM_VERSION version % does not match current config.SYSTEM_VERSION %',
            v_version, v_config_version;
    END IF;

    IF to_regclass('core.return_case') IS NULL
       OR to_regclass('core.payment_refund') IS NULL
       OR to_regclass('core.gift_card_transaction') IS NULL
       OR to_regclass('core.inventory_count') IS NULL
       OR to_regclass('audit.admin_action_attempt') IS NULL THEN
        RAISE EXCEPTION 'One or more required admin operational tables are missing.';
    END IF;

    IF to_regclass('core.admin_order_control_workbench') IS NULL
       OR to_regclass('core.admin_payment_workbench') IS NULL
       OR to_regclass('core.admin_exception_workbench') IS NULL THEN
        RAISE EXCEPTION 'One or more 0.3.15 admin workbench views are missing.';
    END IF;

    IF to_regprocedure('core.amend_order_header(character varying,character varying,jsonb,text,character varying)') IS NULL
       OR to_regprocedure('core.amend_order_line_pre_fulfilment(character varying,character varying,numeric,jsonb,text,character varying)') IS NULL
       OR to_regprocedure('core.move_inventory(character varying,bigint,character varying,character varying,text,character varying,character varying)') IS NULL
       OR to_regprocedure('core.retry_notification(character varying,uuid,character varying)') IS NULL
       OR to_regprocedure('core.retry_order_interface(character varying,uuid,character varying)') IS NULL
       OR to_regprocedure('core.adjust_gift_card(character varying,character varying,numeric,character varying,text,character varying,character varying,character varying)') IS NULL THEN
        RAISE EXCEPTION 'One or more 0.3.15 guarded operational functions are missing.';
    END IF;

    SELECT count(*) INTO v_permission_count
    FROM config.ADMIN_PERMISSION
    WHERE PERMISSION_CODE IN (
      'exception.read','audit.read','system.read','order.amend','order.allocate',
      'order.deallocate','order.pick.create','pick.confirm','shipment.ship',
      'payment.refund','return.manage','inventory.move','inventory.count',
      'notification.retry','interface.retry','promotion.manage','giftcard.manage',
      'supplier.manage','pre_advice.manage'
    );

    IF v_permission_count <> 19 THEN
        RAISE EXCEPTION 'Expected 19 sampled 0.3.15 permissions, got %', v_permission_count;
    END IF;

    SELECT count(*)
      INTO v_missing_owner
      FROM config.ADMIN_ROLE r
      CROSS JOIN config.ADMIN_PERMISSION p
      LEFT JOIN config.ADMIN_ROLE_PERMISSION rp
        ON rp.CLIENT_ID=r.CLIENT_ID
       AND rp.ROLE_CODE=r.ROLE_CODE
       AND rp.PERMISSION_CODE=p.PERMISSION_CODE
     WHERE r.ROLE_CODE='OWNER'
       AND r.ACTIVE=true
       AND rp.PERMISSION_CODE IS NULL;

    IF v_missing_owner <> 0 THEN
        RAISE EXCEPTION 'OWNER role is missing % permission(s)', v_missing_owner;
    END IF;

    SELECT count(*) INTO v_reason_count
    FROM config.ADMIN_REASON_CODE
    WHERE CLIENT_ID='FINATICS';

    IF v_reason_count < 20 THEN
        RAISE EXCEPTION 'Expected at least 20 FINATICS admin reason codes, got %', v_reason_count;
    END IF;

    RAISE NOTICE 'PASS: DYNETIC WMS admin operations control-plane regression verified.';
END
$test$;

ROLLBACK;
