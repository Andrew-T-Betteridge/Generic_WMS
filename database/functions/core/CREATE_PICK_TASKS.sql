CREATE OR REPLACE FUNCTION core.CREATE_PICK_TASKS (
    p_client_id VARCHAR,
    p_order_id VARCHAR,
    p_created_by VARCHAR DEFAULT 'SYSTEM'
)
RETURNS TABLE (
    RESULT_STATUS VARCHAR,
    RESULT_ORDER_ID VARCHAR,
    RESULT_TASKS_CREATED INTEGER,
    RESULT_QTY_TASKED NUMERIC,
    RESULT_MESSAGE TEXT
)
LANGUAGE plpgsql
AS $$
DECLARE
    v_created INTEGER := 0;
    v_qty NUMERIC(15,6) := 0;
    v_row RECORD;
    v_open NUMERIC(15,6);
BEGIN
    IF NOT EXISTS (SELECT 1 FROM core.ORDER_HEADER WHERE CLIENT_ID=p_client_id AND ORDER_ID=p_order_id) THEN
        RETURN QUERY SELECT 'ERROR'::VARCHAR,p_order_id::VARCHAR,0,0::NUMERIC,'Order does not exist.'::TEXT;
        RETURN;
    END IF;

    FOR v_row IN
        SELECT a.ALLOCATION_ID,a.CLIENT_ID,a.ORDER_ID,a.LINE_ID,a.INVENTORY_KEY,
               a.QTY_ALLOCATED,a.QTY_PICKED,a.QTY_RELEASED,
               ol.SKU_ID,i.LOCATION_ID,i.BATCH_ID
        FROM core.ALLOCATION a
        JOIN core.ORDER_LINE ol ON ol.CLIENT_ID=a.CLIENT_ID AND ol.ORDER_ID=a.ORDER_ID AND ol.LINE_ID=a.LINE_ID
        JOIN core.INVENTORY i ON i.KEY=a.INVENTORY_KEY
        WHERE a.CLIENT_ID=p_client_id AND a.ORDER_ID=p_order_id
          AND (a.QTY_ALLOCATED-a.QTY_PICKED-a.QTY_RELEASED)>0
          AND NOT EXISTS (SELECT 1 FROM core.PICK_TASK pt WHERE pt.ALLOCATION_ID=a.ALLOCATION_ID)
        ORDER BY a.LINE_ID,a.ALLOCATION_ID
        FOR UPDATE OF a
    LOOP
        v_open := v_row.QTY_ALLOCATED-v_row.QTY_PICKED-v_row.QTY_RELEASED;
        INSERT INTO core.PICK_TASK (
            CLIENT_ID,ORDER_ID,LINE_ID,ALLOCATION_ID,INVENTORY_KEY,SKU_ID,LOCATION_ID,BATCH_ID,
            QTY_REQUIRED,CREATED_BY,LAST_UPDATED_BY
        ) VALUES (
            v_row.CLIENT_ID,v_row.ORDER_ID,v_row.LINE_ID,v_row.ALLOCATION_ID,v_row.INVENTORY_KEY,
            v_row.SKU_ID,v_row.LOCATION_ID,v_row.BATCH_ID,v_open,
            COALESCE(NULLIF(p_created_by,''),'SYSTEM'),COALESCE(NULLIF(p_created_by,''),'SYSTEM')
        );
        v_created := v_created+1;
        v_qty := v_qty+v_open;
    END LOOP;

    UPDATE core.ORDER_LINE ol
    SET QTY_TASKED = COALESCE(ol.QTY_PICKED,0) + COALESCE((
            SELECT SUM(GREATEST(0,pt.QTY_REQUIRED-pt.QTY_PICKED-pt.SHORT_QTY))
            FROM core.PICK_TASK pt
            WHERE pt.CLIENT_ID=ol.CLIENT_ID AND pt.ORDER_ID=ol.ORDER_ID AND pt.LINE_ID=ol.LINE_ID
              AND pt.STATUS IN ('OPEN','PART_PICKED')
        ),0),
        LAST_UPDATED_BY='CREATE_PICK_TASKS',LAST_UPDATE_DATE=now()
    WHERE ol.CLIENT_ID=p_client_id AND ol.ORDER_ID=p_order_id;

    IF v_created>0 THEN
        UPDATE core.ORDER_HEADER SET FULFILMENT_STATUS='PICKING',LAST_UPDATED_BY='CREATE_PICK_TASKS',LAST_UPDATE_DATE=now()
        WHERE CLIENT_ID=p_client_id AND ORDER_ID=p_order_id;
    END IF;

    RETURN QUERY SELECT
        CASE WHEN v_created=0 THEN 'NO_NEW_TASKS' ELSE 'TASKS_CREATED' END::VARCHAR,
        p_order_id::VARCHAR,v_created,v_qty::NUMERIC,
        CASE WHEN v_created=0 THEN 'No untasked open allocations were found.'
             ELSE format('Created %s pick task(s) for %s unit(s).',v_created,v_qty) END::TEXT;
END;
$$;
