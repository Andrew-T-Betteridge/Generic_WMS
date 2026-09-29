BEGIN;

-- Complete runtime privileges for the Generic WMS Admin control plane
-- introduced by migration 0032.
--
-- The application role is derived from the owner of the core schema rather
-- than hard-coded to a deployment-specific role.
--
-- Functions introduced by 0032 execute with PostgreSQL's default
-- SECURITY INVOKER behaviour, therefore the runtime role requires the
-- underlying table privileges used by those functions as well as EXECUTE.

DO $$
DECLARE
    v_app_role name;
BEGIN
    SELECT pg_get_userbyid(nspowner)
      INTO v_app_role
      FROM pg_namespace
     WHERE nspname = 'core';

    IF v_app_role IS NULL THEN
        RAISE EXCEPTION 'CORE_SCHEMA_OWNER_NOT_FOUND';
    END IF;

    -- Admin configuration reads.
    EXECUTE format(
        'GRANT SELECT ON config.admin_reason_code, config.admin_operational_sla TO %I',
        v_app_role
    );

    -- Admin control-plane reads.
    EXECUTE format(
        'GRANT SELECT ON core.order_note, core.customer_note, core.return_case, core.return_case_line, core.payment_refund, core.gift_card_transaction, core.inventory_count, core.inventory_count_line TO %I',
        v_app_role
    );

    -- Underlying DML required by SECURITY INVOKER Admin functions.
    EXECUTE format(
        'GRANT INSERT ON core.order_note TO %I',
        v_app_role
    );

    EXECUTE format(
        'GRANT UPDATE ON core.order_header, core.order_line TO %I',
        v_app_role
    );

    EXECUTE format(
        'GRANT UPDATE ON core.inventory TO %I',
        v_app_role
    );

    EXECUTE format(
        'GRANT INSERT ON core.inventory_transaction TO %I',
        v_app_role
    );

    EXECUTE format(
        'GRANT UPDATE ON interface.order_header_if TO %I',
        v_app_role
    );

    EXECUTE format(
        'GRANT SELECT, UPDATE ON core.gift_card TO %I',
        v_app_role
    );

    EXECUTE format(
        'GRANT INSERT ON core.gift_card_transaction TO %I',
        v_app_role
    );

    -- Admin action audit trail.
    EXECUTE format(
        'GRANT SELECT, INSERT ON audit.admin_action_attempt TO %I',
        v_app_role
    );

    -- Controlled Admin operations introduced by migration 0032.
    EXECUTE format(
        'GRANT EXECUTE ON FUNCTION core.add_order_note(varchar,varchar,varchar,text,boolean,varchar) TO %I',
        v_app_role
    );

    EXECUTE format(
        'GRANT EXECUTE ON FUNCTION core.amend_order_header(varchar,varchar,jsonb,text,varchar) TO %I',
        v_app_role
    );

    EXECUTE format(
        'GRANT EXECUTE ON FUNCTION core.amend_order_line_pre_fulfilment(varchar,varchar,numeric,jsonb,text,varchar) TO %I',
        v_app_role
    );

    EXECUTE format(
        'GRANT EXECUTE ON FUNCTION core.move_inventory(varchar,bigint,varchar,varchar,text,varchar,varchar) TO %I',
        v_app_role
    );

    EXECUTE format(
        'GRANT EXECUTE ON FUNCTION core.retry_notification(varchar,uuid,varchar) TO %I',
        v_app_role
    );

    EXECUTE format(
        'GRANT EXECUTE ON FUNCTION core.retry_order_interface(varchar,uuid,varchar) TO %I',
        v_app_role
    );

    EXECUTE format(
        'GRANT EXECUTE ON FUNCTION core.adjust_gift_card(varchar,varchar,numeric,varchar,text,varchar,varchar,varchar) TO %I',
        v_app_role
    );
END
$$;

COMMIT;
