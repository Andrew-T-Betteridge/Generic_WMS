-- Releases only the still-reserved quantity. Picked stock is never reversed by
-- deallocation. Allocation and pick-task history is retained for auditability.
CREATE OR REPLACE FUNCTION core.DEALLOCATE_ORDER (
    p_client_id VARCHAR,
    p_order_id  VARCHAR
)
RETURNS TABLE (
    RESULT_STATUS        VARCHAR,
    RESULT_ORDER_ID      VARCHAR,
    RESULT_ALLOCATIONS   INTEGER,
    RESULT_QTY_RELEASED  NUMERIC,
    RESULT_MESSAGE       TEXT
)
LANGUAGE plpgsql
AS $$
DECLARE
    v_alloc RECORD;
    v_open_qty NUMERIC(15,6);
    v_count INTEGER := 0;
    v_qty_released NUMERIC(15,6) := 0;
BEGIN
    IF NOT EXISTS (SELECT 1 FROM core.ORDER_HEADER WHERE CLIENT_ID=p_client_id AND ORDER_ID=p_order_id) THEN
        RETURN QUERY SELECT 'ERROR'::VARCHAR, p_order_id::VARCHAR, 0, 0::NUMERIC, 'Order does not exist.'::TEXT;
        RETURN;
    END IF;

    FOR v_alloc IN
        SELECT a.*
        FROM core.ALLOCATION a
        WHERE a.CLIENT_ID=p_client_id AND a.ORDER_ID=p_order_id
          AND (a.QTY_ALLOCATED - a.QTY_PICKED - a.QTY_RELEASED) > 0
        ORDER BY a.ALLOCATION_ID
        FOR UPDATE
    LOOP
        v_open_qty := v_alloc.QTY_ALLOCATED - v_alloc.QTY_PICKED - v_alloc.QTY_RELEASED;

        UPDATE core.INVENTORY
        SET QTY_ALLOCATED = GREATEST(0, QTY_ALLOCATED - v_open_qty)
        WHERE KEY = v_alloc.INVENTORY_KEY;

        UPDATE core.ALLOCATION
        SET QTY_RELEASED = QTY_RELEASED + v_open_qty,
            STATUS = CASE WHEN QTY_PICKED > 0 THEN 'PART_PICKED_RELEASED' ELSE 'RELEASED' END,
            LAST_UPDATE_DSTAMP = now(), LAST_UPDATED_BY = 'DEALLOCATE_ORDER'
        WHERE ALLOCATION_ID = v_alloc.ALLOCATION_ID;

        UPDATE core.PICK_TASK
        SET SHORT_QTY = LEAST(QTY_REQUIRED - QTY_PICKED, SHORT_QTY + v_open_qty),
            STATUS = CASE WHEN QTY_PICKED > 0 THEN 'SHORT' ELSE 'CANCELLED' END,
            SHORT_REASON = COALESCE(SHORT_REASON, 'Allocation released'),
            COMPLETED_DSTAMP = now(), LAST_UPDATE_DSTAMP = now(), LAST_UPDATED_BY='DEALLOCATE_ORDER'
        WHERE ALLOCATION_ID = v_alloc.ALLOCATION_ID
          AND STATUS IN ('OPEN','PART_PICKED');

        v_count := v_count + 1;
        v_qty_released := v_qty_released + v_open_qty;
    END LOOP;

    UPDATE core.ORDER_LINE ol
    SET QTY_SOFT_ALLOCATED = COALESCE((
            SELECT SUM(GREATEST(0, a.QTY_ALLOCATED-a.QTY_PICKED-a.QTY_RELEASED))
            FROM core.ALLOCATION a
            WHERE a.CLIENT_ID=ol.CLIENT_ID AND a.ORDER_ID=ol.ORDER_ID AND a.LINE_ID=ol.LINE_ID
        ),0),
        BACK_ORDERED = CASE WHEN COALESCE(ol.QTY_PICKED,0) >= ol.QTY_ORDERED THEN 'N' ELSE 'Y' END,
        LAST_UPDATED_BY='DEALLOCATE_ORDER', LAST_UPDATE_DATE=now()
    WHERE ol.CLIENT_ID=p_client_id AND ol.ORDER_ID=p_order_id;

    UPDATE core.ORDER_HEADER
    SET FULFILMENT_STATUS = CASE
            WHEN EXISTS (SELECT 1 FROM core.ORDER_LINE WHERE CLIENT_ID=p_client_id AND ORDER_ID=p_order_id AND COALESCE(QTY_PICKED,0)>0)
                THEN 'PART_PICKED'
            ELSE 'UNALLOCATED' END,
        LAST_UPDATED_BY='DEALLOCATE_ORDER', LAST_UPDATE_DATE=now()
    WHERE CLIENT_ID=p_client_id AND ORDER_ID=p_order_id;

    RETURN QUERY SELECT
        CASE WHEN v_count=0 THEN 'NOT_ALLOCATED' ELSE 'DEALLOCATED' END::VARCHAR,
        p_order_id::VARCHAR, v_count, v_qty_released::NUMERIC,
        CASE WHEN v_count=0 THEN 'Order had no open reservations to release.'
             ELSE format('Released %s open allocation(s), totalling %s unit(s). Allocation history retained.',v_count,v_qty_released)
        END::TEXT;
END;
$$;
