DO $$
DECLARE
    v_app_role name;
BEGIN
    SELECT pg_get_userbyid(nspowner)
      INTO v_app_role
      FROM pg_namespace
     WHERE nspname = 'core';

    IF v_app_role IS NULL THEN
        RAISE EXCEPTION 'FAIL: core schema owner not found';
    END IF;

    -- Configuration reads.
    IF NOT has_table_privilege(v_app_role, 'config.admin_reason_code', 'SELECT')
       OR NOT has_table_privilege(v_app_role, 'config.admin_operational_sla', 'SELECT') THEN
        RAISE EXCEPTION 'FAIL: Admin configuration read privileges';
    END IF;

    -- Control-plane reads.
    IF NOT has_table_privilege(v_app_role, 'core.order_note', 'SELECT')
       OR NOT has_table_privilege(v_app_role, 'core.customer_note', 'SELECT')
       OR NOT has_table_privilege(v_app_role, 'core.return_case', 'SELECT')
       OR NOT has_table_privilege(v_app_role, 'core.return_case_line', 'SELECT')
       OR NOT has_table_privilege(v_app_role, 'core.payment_refund', 'SELECT')
       OR NOT has_table_privilege(v_app_role, 'core.gift_card_transaction', 'SELECT')
       OR NOT has_table_privilege(v_app_role, 'core.inventory_count', 'SELECT')
       OR NOT has_table_privilege(v_app_role, 'core.inventory_count_line', 'SELECT') THEN
        RAISE EXCEPTION 'FAIL: Admin control-plane read privileges';
    END IF;

    -- SECURITY INVOKER function dependencies.
    IF NOT has_table_privilege(v_app_role, 'core.order_note', 'INSERT') THEN
        RAISE EXCEPTION 'FAIL: order_note INSERT';
    END IF;

    IF NOT has_table_privilege(v_app_role, 'core.order_header', 'UPDATE')
       OR NOT has_table_privilege(v_app_role, 'core.order_line', 'UPDATE') THEN
        RAISE EXCEPTION 'FAIL: order amendment UPDATE privileges';
    END IF;

    IF NOT has_table_privilege(v_app_role, 'core.inventory', 'UPDATE')
       OR NOT has_table_privilege(v_app_role, 'core.inventory_transaction', 'INSERT') THEN
        RAISE EXCEPTION 'FAIL: inventory move privileges';
    END IF;

    IF NOT has_table_privilege(v_app_role, 'interface.notification_outbox', 'UPDATE')
       OR NOT has_table_privilege(v_app_role, 'interface.order_header_if', 'UPDATE') THEN
        RAISE EXCEPTION 'FAIL: retry privileges';
    END IF;

    IF NOT has_table_privilege(v_app_role, 'core.gift_card', 'SELECT')
       OR NOT has_table_privilege(v_app_role, 'core.gift_card', 'UPDATE')
       OR NOT has_table_privilege(v_app_role, 'core.gift_card_transaction', 'INSERT') THEN
        RAISE EXCEPTION 'FAIL: gift card adjustment privileges';
    END IF;

    IF NOT has_table_privilege(v_app_role, 'audit.audit_event', 'INSERT') THEN
        RAISE EXCEPTION 'FAIL: audit_event INSERT';
    END IF;

    IF NOT has_table_privilege(v_app_role, 'audit.admin_action_attempt', 'SELECT') THEN
        RAISE EXCEPTION 'FAIL: admin_action_attempt SELECT';
    END IF;

    IF NOT has_table_privilege(v_app_role, 'audit.admin_action_attempt', 'INSERT') THEN
        RAISE EXCEPTION 'FAIL: admin_action_attempt INSERT';
    END IF;

    -- Function execution.
    IF NOT has_function_privilege(v_app_role, 'core.add_order_note(varchar,varchar,varchar,text,boolean,varchar)', 'EXECUTE')
       OR NOT has_function_privilege(v_app_role, 'core.amend_order_header(varchar,varchar,jsonb,text,varchar)', 'EXECUTE')
       OR NOT has_function_privilege(v_app_role, 'core.amend_order_line_pre_fulfilment(varchar,varchar,numeric,jsonb,text,varchar)', 'EXECUTE')
       OR NOT has_function_privilege(v_app_role, 'core.move_inventory(varchar,bigint,varchar,varchar,text,varchar,varchar)', 'EXECUTE')
       OR NOT has_function_privilege(v_app_role, 'core.retry_notification(varchar,uuid,varchar)', 'EXECUTE')
       OR NOT has_function_privilege(v_app_role, 'core.retry_order_interface(varchar,uuid,varchar)', 'EXECUTE')
       OR NOT has_function_privilege(v_app_role, 'core.adjust_gift_card(varchar,varchar,numeric,varchar,text,varchar,varchar,varchar)', 'EXECUTE') THEN
        RAISE EXCEPTION 'FAIL: one or more Admin function EXECUTE privileges missing';
    END IF;

    RAISE NOTICE 'PASS: Admin control-plane runtime privileges complete for role %', v_app_role;
END
$$;
