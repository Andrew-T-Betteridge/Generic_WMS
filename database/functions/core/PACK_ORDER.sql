-- V1 packing: place all currently-picked, not-yet-packed task quantity into a
-- single order container. SHIPPING_MANIFEST acts as the container-content line.
CREATE OR REPLACE FUNCTION core.PACK_ORDER (
    p_client_id VARCHAR,
    p_order_id VARCHAR,
    p_container_id VARCHAR,
    p_user_id VARCHAR DEFAULT 'SYSTEM',
    p_station_id VARCHAR DEFAULT 'WMS'
)
RETURNS TABLE (
    RESULT_STATUS VARCHAR,
    RESULT_CONTAINER_ID VARCHAR,
    RESULT_ROWS_PACKED INTEGER,
    RESULT_QTY_PACKED NUMERIC,
    RESULT_MESSAGE TEXT
)
LANGUAGE plpgsql
AS $$
DECLARE
    v_task RECORD;
    v_qty NUMERIC(15,6);
    v_rows INTEGER := 0;
    v_total NUMERIC(15,6) := 0;
    v_user VARCHAR(20) := LEFT(COALESCE(NULLIF(p_user_id,''),'SYSTEM'),20);
    v_station VARCHAR(256) := LEFT(COALESCE(NULLIF(p_station_id,''),'WMS'),256);
BEGIN
    IF p_container_id IS NULL OR btrim(p_container_id)='' THEN
        RETURN QUERY SELECT 'ERROR'::VARCHAR,p_container_id::VARCHAR,0,0::NUMERIC,'Container ID is required.'::TEXT;
        RETURN;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM core.ORDER_HEADER WHERE CLIENT_ID=p_client_id AND ORDER_ID=p_order_id) THEN
        RETURN QUERY SELECT 'ERROR'::VARCHAR,p_container_id::VARCHAR,0,0::NUMERIC,'Order does not exist.'::TEXT;
        RETURN;
    END IF;
    IF EXISTS (SELECT 1 FROM core.ORDER_CONTAINER WHERE CLIENT_ID=p_client_id AND CONTAINER_ID=p_container_id AND ORDER_ID<>p_order_id) THEN
        RETURN QUERY SELECT 'ERROR'::VARCHAR,p_container_id::VARCHAR,0,0::NUMERIC,'Container belongs to another order.'::TEXT;
        RETURN;
    END IF;

    INSERT INTO core.ORDER_CONTAINER (CLIENT_ID,ORDER_ID,CONTAINER_ID,STATUS)
    VALUES (p_client_id,p_order_id,p_container_id,'OPEN')
    ON CONFLICT (CLIENT_ID,CONTAINER_ID) DO NOTHING;

    FOR v_task IN
        SELECT pt.*, i.SITE_ID,i.OWNER_ID,i.TAG_ID,i.CONTAINER_ID AS INVENTORY_CONTAINER_ID,
               i.CONDITION_ID,i.LOCK_STATUS,i.LOCK_CODE,i.ORIGIN_ID,i.SUPPLIER_ID,
               COALESCE((SELECT SUM(sm.QTY_PICKED) FROM core.SHIPPING_MANIFEST sm WHERE sm.PICK_TASK_ID=pt.PICK_TASK_ID),0) AS ALREADY_PACKED
        FROM core.PICK_TASK pt
        JOIN core.INVENTORY i ON i.KEY=pt.INVENTORY_KEY
        WHERE pt.CLIENT_ID=p_client_id AND pt.ORDER_ID=p_order_id AND pt.QTY_PICKED>0
        ORDER BY pt.LINE_ID,pt.PICK_TASK_ID
        FOR UPDATE OF pt
    LOOP
        v_qty := v_task.QTY_PICKED-v_task.ALREADY_PACKED;
        CONTINUE WHEN v_qty<=0;

        INSERT INTO core.SHIPPING_MANIFEST (
            CLIENT_ID,ORDER_ID,LINE_ID,SKU_ID,BATCH_ID,CONTAINER_ID,SITE_ID,LOCATION_ID,OWNER_ID,
            QTY_PICKED,PICKED_DSTAMP,QTY_SHIPPED,SHIPPED,STATION_ID,USER_ID,SUPPLIER_ID,ORIGIN_ID,
            CONDITION_ID,LOCK_STATUS,LOCK_CODE,STATUS,PICK_TASK_ID
        ) VALUES (
            p_client_id,p_order_id,v_task.LINE_ID,v_task.SKU_ID,v_task.BATCH_ID,p_container_id,
            v_task.SITE_ID,v_task.LOCATION_ID,v_task.OWNER_ID,v_qty,now(),0,'N',v_station,v_user,
            v_task.SUPPLIER_ID,v_task.ORIGIN_ID,v_task.CONDITION_ID,v_task.LOCK_STATUS,v_task.LOCK_CODE,
            'PACKED',v_task.PICK_TASK_ID
        );
        v_rows:=v_rows+1; v_total:=v_total+v_qty;
    END LOOP;

    IF v_rows=0 THEN
        RETURN QUERY SELECT 'NOTHING_TO_PACK'::VARCHAR,p_container_id::VARCHAR,0,0::NUMERIC,'No picked quantity remains unpacked.'::TEXT;
        RETURN;
    END IF;

    UPDATE core.ORDER_CONTAINER SET STATUS='PACKED',CLOSED_DSTAMP=now()
    WHERE CLIENT_ID=p_client_id AND CONTAINER_ID=p_container_id;

    UPDATE core.ORDER_HEADER oh
    SET FULFILMENT_STATUS=CASE
            WHEN NOT EXISTS (
                SELECT 1 FROM core.ORDER_LINE ol
                WHERE ol.CLIENT_ID=p_client_id AND ol.ORDER_ID=p_order_id
                  AND COALESCE((SELECT SUM(sm.QTY_PICKED) FROM core.SHIPPING_MANIFEST sm
                                WHERE sm.CLIENT_ID=ol.CLIENT_ID AND sm.ORDER_ID=ol.ORDER_ID AND sm.LINE_ID=ol.LINE_ID),0) < ol.QTY_ORDERED
            ) THEN 'READY_TO_SHIP'
            ELSE 'PART_PACKED' END,
        LAST_UPDATED_BY=v_user,LAST_UPDATE_DATE=now()
    WHERE oh.CLIENT_ID=p_client_id AND oh.ORDER_ID=p_order_id;

    RETURN QUERY SELECT 'PACKED'::VARCHAR,p_container_id::VARCHAR,v_rows,v_total::NUMERIC,
        format('Packed %s manifest row(s), totalling %s unit(s), into container %s.',v_rows,v_total,p_container_id)::TEXT;
END;
$$;
