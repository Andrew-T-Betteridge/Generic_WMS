BEGIN;

CREATE OR REPLACE FUNCTION core.ADJUST_INVENTORY (
    p_client_id       VARCHAR,
    p_inventory_key   BIGINT,
    p_adjustment_qty  NUMERIC,
    p_reason_code     VARCHAR,
    p_notes           TEXT DEFAULT NULL,
    p_user_id         VARCHAR DEFAULT 'SYSTEM',
    p_station_id      VARCHAR DEFAULT 'ADMIN'
)
RETURNS TABLE (
    RESULT_STATUS       VARCHAR,
    RESULT_INVENTORY_KEY BIGINT,
    RESULT_SKU_ID       VARCHAR,
    RESULT_LOCATION_ID  VARCHAR,
    RESULT_OLD_QTY      NUMERIC,
    RESULT_ADJUSTMENT   NUMERIC,
    RESULT_NEW_QTY      NUMERIC,
    RESULT_ALLOCATED_QTY NUMERIC,
    RESULT_AVAILABLE_QTY NUMERIC,
    RESULT_MESSAGE      TEXT
)
LANGUAGE plpgsql
AS $$
DECLARE
    v_inv core.INVENTORY%ROWTYPE;
    v_new_qty NUMERIC(15,6);
    v_user VARCHAR(20) := LEFT(COALESCE(NULLIF(p_user_id,''),'SYSTEM'),20);
    v_station VARCHAR(256) := LEFT(COALESCE(NULLIF(p_station_id,''),'ADMIN'),256);
    v_reason VARCHAR(10) := LEFT(UPPER(COALESCE(NULLIF(p_reason_code,''),'ADJUST')),10);
BEGIN
    IF p_adjustment_qty IS NULL OR p_adjustment_qty = 0 THEN
        RAISE EXCEPTION 'INVALID_ADJUSTMENT_QTY';
    END IF;

    SELECT *
      INTO v_inv
      FROM core.INVENTORY
     WHERE CLIENT_ID=p_client_id
       AND KEY=p_inventory_key
     FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'INVENTORY_NOT_FOUND';
    END IF;

    v_new_qty := v_inv.QTY_ON_HAND + p_adjustment_qty;

    IF v_new_qty < 0 THEN
        RAISE EXCEPTION 'ADJUSTMENT_WOULD_MAKE_STOCK_NEGATIVE';
    END IF;

    IF v_new_qty < COALESCE(v_inv.QTY_ALLOCATED,0) THEN
        RAISE EXCEPTION 'ADJUSTMENT_BELOW_ALLOCATED_QTY';
    END IF;

    UPDATE core.INVENTORY
       SET QTY_ON_HAND=v_new_qty,
           MOVE_DSTAMP=now()
     WHERE KEY=v_inv.KEY;

    INSERT INTO core.INVENTORY_TRANSACTION (
        CODE,SITE_ID,FROM_SITE_ID,TO_SITE_ID,FROM_LOC_ID,TO_LOC_ID,FINAL_LOC_ID,
        OWNER_ID,CLIENT_ID,SKU_ID,TAG_ID,CONTAINER_ID,BATCH_ID,QC_STATUS,
        EXPIRY_DSTAMP,MANUF_DSTAMP,ORIGIN_ID,CONDITION_ID,LOCK_STATUS,DSTAMP,
        SUPPLIER_ID,REFERENCE_ID,REASON_ID,STATION_ID,USER_ID,UPDATE_QTY,
        ORIGINAL_QTY,COMPLETE_DSTAMP,NOTES,LOCK_CODE,SOURCE,REFERENCE_TYPE
    ) VALUES (
        'ADJUSTMENT',
        v_inv.SITE_ID,v_inv.SITE_ID,v_inv.SITE_ID,
        v_inv.LOCATION_ID,v_inv.LOCATION_ID,v_inv.LOCATION_ID,
        v_inv.OWNER_ID,v_inv.CLIENT_ID,v_inv.SKU_ID,v_inv.TAG_ID,
        v_inv.CONTAINER_ID,v_inv.BATCH_ID,v_inv.QC_STATUS,
        v_inv.EXPIRY_DSTAMP,v_inv.MANUF_DSTAMP,v_inv.ORIGIN_ID,
        v_inv.CONDITION_ID,v_inv.LOCK_STATUS,now(),
        v_inv.SUPPLIER_ID,LEFT(v_inv.KEY::text,20),v_reason,
        v_station,v_user,p_adjustment_qty,v_inv.QTY_ON_HAND,
        now(),LEFT(COALESCE(p_notes,''),400),v_inv.LOCK_CODE,
        'ADMIN_PORTAL','INVENTORY'
    );

    RETURN QUERY SELECT
        'ADJUSTED'::VARCHAR,
        v_inv.KEY,
        v_inv.SKU_ID,
        v_inv.LOCATION_ID,
        v_inv.QTY_ON_HAND::NUMERIC,
        p_adjustment_qty::NUMERIC,
        v_new_qty::NUMERIC,
        COALESCE(v_inv.QTY_ALLOCATED,0)::NUMERIC,
        (v_new_qty-COALESCE(v_inv.QTY_ALLOCATED,0))::NUMERIC,
        format(
            'Adjusted inventory %s by %s unit(s): %s -> %s.',
            v_inv.KEY,p_adjustment_qty,v_inv.QTY_ON_HAND,v_new_qty
        )::TEXT;
END;
$$;

CREATE OR REPLACE FUNCTION core.CANCEL_ORDER (
    p_client_id    VARCHAR,
    p_order_id     VARCHAR,
    p_reason_code  VARCHAR,
    p_user_id      VARCHAR DEFAULT 'SYSTEM'
)
RETURNS TABLE (
    RESULT_STATUS             VARCHAR,
    RESULT_ORDER_ID           VARCHAR,
    RESULT_PAYMENT_STATUS     VARCHAR,
    RESULT_REFUND_RECOMMENDED BOOLEAN,
    RESULT_MESSAGE            TEXT
)
LANGUAGE plpgsql
AS $$
DECLARE
    v_order core.ORDER_HEADER%ROWTYPE;
    v_user VARCHAR(20) := LEFT(COALESCE(NULLIF(p_user_id,''),'SYSTEM'),20);
    v_reason VARCHAR(10) := LEFT(UPPER(COALESCE(NULLIF(p_reason_code,''),'CANCEL')),10);
BEGIN
    SELECT *
      INTO v_order
      FROM core.ORDER_HEADER
     WHERE CLIENT_ID=p_client_id
       AND ORDER_ID=p_order_id
     FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'ORDER_NOT_FOUND';
    END IF;

    IF UPPER(COALESCE(v_order.STATUS,''))='CANCELLED'
       OR UPPER(COALESCE(v_order.FULFILMENT_STATUS,''))='CANCELLED' THEN
        RETURN QUERY SELECT
            'ALREADY_CANCELLED'::VARCHAR,
            p_order_id::VARCHAR,
            v_order.PAYMENT_STATUS::VARCHAR,
            (UPPER(COALESCE(v_order.PAYMENT_STATUS,'')) IN ('PAID','PART_REFUNDED'))::BOOLEAN,
            'Order is already cancelled.'::TEXT;
        RETURN;
    END IF;

    IF v_order.SHIPPED_DATE IS NOT NULL
       OR v_order.DELIVERED_DSTAMP IS NOT NULL
       OR EXISTS (
            SELECT 1
              FROM core.ORDER_LINE
             WHERE CLIENT_ID=p_client_id AND ORDER_ID=p_order_id
               AND (COALESCE(QTY_SHIPPED,0)>0 OR COALESCE(QTY_DELIVERED,0)>0)
       ) THEN
        RAISE EXCEPTION 'ORDER_ALREADY_SHIPPED';
    END IF;

    IF EXISTS (
        SELECT 1
          FROM core.ORDER_LINE
         WHERE CLIENT_ID=p_client_id AND ORDER_ID=p_order_id
           AND COALESCE(QTY_PICKED,0)>0
    ) THEN
        RAISE EXCEPTION 'ORDER_ALREADY_PICKED';
    END IF;

    IF UPPER(COALESCE(v_order.PAYMENT_STATUS,'')) IN ('PENDING','AUTHORISED') THEN
        RAISE EXCEPTION 'PAYMENT_STATE_REQUIRES_ACTION';
    END IF;

    PERFORM * FROM core.DEALLOCATE_ORDER(p_client_id,p_order_id);

    UPDATE core.ORDER_HEADER
       SET STATUS='CANCELLED',
           FULFILMENT_STATUS='CANCELLED',
           STATUS_REASON_CODE=v_reason,
           ORDER_CLOSED='Y',
           CLOSURE_DATE=COALESCE(CLOSURE_DATE,now()),
           LAST_UPDATED_BY=v_user,
           LAST_UPDATE_DATE=now()
     WHERE CLIENT_ID=p_client_id
       AND ORDER_ID=p_order_id;

    RETURN QUERY SELECT
        'CANCELLED'::VARCHAR,
        p_order_id::VARCHAR,
        v_order.PAYMENT_STATUS::VARCHAR,
        (UPPER(COALESCE(v_order.PAYMENT_STATUS,'')) IN ('PAID','PART_REFUNDED'))::BOOLEAN,
        CASE
          WHEN UPPER(COALESCE(v_order.PAYMENT_STATUS,'')) IN ('PAID','PART_REFUNDED')
            THEN 'Order cancelled and open stock released. Payment remains captured; review refund separately.'
          ELSE 'Order cancelled and open stock released.'
        END::TEXT;
END;
$$;

-- Migration 0025 was intentionally executed by a privileged migration role.
-- Make its table privileges reproducible by granting them to the application
-- role represented by the owner of the core schema, instead of hard-coding
-- a deployment-specific role name.
DO $$
DECLARE
    v_app_role name;
BEGIN
    SELECT pg_get_userbyid(nspowner)
      INTO v_app_role
      FROM pg_namespace
     WHERE nspname='core';

    IF v_app_role IS NULL THEN
        RAISE EXCEPTION 'CORE_SCHEMA_OWNER_NOT_FOUND';
    END IF;

    EXECUTE format('GRANT USAGE ON SCHEMA config,audit,core TO %I',v_app_role);
    EXECUTE format(
        'GRANT SELECT,INSERT,UPDATE,DELETE ON config.admin_permission,config.admin_role,config.admin_role_permission,config.admin_user,config.admin_user_role TO %I',
        v_app_role
    );
    EXECUTE format('GRANT SELECT,INSERT ON audit.audit_event TO %I',v_app_role);
    EXECUTE format('GRANT EXECUTE ON FUNCTION core.ADJUST_INVENTORY(varchar,bigint,numeric,varchar,text,varchar,varchar) TO %I',v_app_role);
    EXECUTE format('GRANT EXECUTE ON FUNCTION core.CANCEL_ORDER(varchar,varchar,varchar,varchar) TO %I',v_app_role);

    IF pg_get_serial_sequence('audit.audit_event','audit_id') IS NOT NULL THEN
        EXECUTE format(
            'GRANT USAGE,SELECT ON SEQUENCE %s TO %I',
            pg_get_serial_sequence('audit.audit_event','audit_id'),
            v_app_role
        );
    END IF;
END
$$;

COMMIT;
