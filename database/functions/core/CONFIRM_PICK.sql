CREATE OR REPLACE FUNCTION core.CONFIRM_PICK (
    p_pick_task_id BIGINT,
    p_qty_picked NUMERIC,
    p_user_id VARCHAR DEFAULT 'SYSTEM',
    p_station_id VARCHAR DEFAULT 'WMS',
    p_short_close BOOLEAN DEFAULT FALSE,
    p_short_reason VARCHAR DEFAULT NULL
)
RETURNS TABLE (
    RESULT_STATUS VARCHAR,
    RESULT_PICK_TASK_ID BIGINT,
    RESULT_QTY_PICKED NUMERIC,
    RESULT_QTY_SHORT NUMERIC,
    RESULT_MESSAGE TEXT
)
LANGUAGE plpgsql
AS $$
DECLARE
    v_task RECORD;
    v_alloc RECORD;
    v_inv RECORD;
    v_task_remaining NUMERIC(15,6);
    v_alloc_remaining NUMERIC(15,6);
    v_short NUMERIC(15,6) := 0;
    v_user VARCHAR(20) := LEFT(COALESCE(NULLIF(p_user_id,''),'SYSTEM'),20);
    v_station VARCHAR(256) := LEFT(COALESCE(NULLIF(p_station_id,''),'WMS'),256);
BEGIN
    SELECT * INTO v_task FROM core.PICK_TASK WHERE PICK_TASK_ID=p_pick_task_id FOR UPDATE;
    IF NOT FOUND THEN
        RETURN QUERY SELECT 'ERROR'::VARCHAR,p_pick_task_id,0::NUMERIC,0::NUMERIC,'Pick task does not exist.'::TEXT;
        RETURN;
    END IF;

    IF v_task.STATUS NOT IN ('OPEN','PART_PICKED') THEN
        RETURN QUERY SELECT 'ERROR'::VARCHAR,p_pick_task_id,0::NUMERIC,0::NUMERIC,
            format('Pick task is already %s.',v_task.STATUS)::TEXT;
        RETURN;
    END IF;

    IF p_qty_picked < 0 OR (p_qty_picked = 0 AND NOT p_short_close) THEN
        RETURN QUERY SELECT 'ERROR'::VARCHAR,p_pick_task_id,0::NUMERIC,0::NUMERIC,
            'Pick quantity must be positive, unless zero is being short-closed.'::TEXT;
        RETURN;
    END IF;

    v_task_remaining := v_task.QTY_REQUIRED-v_task.QTY_PICKED-v_task.SHORT_QTY;
    IF p_qty_picked > v_task_remaining THEN
        RETURN QUERY SELECT 'ERROR'::VARCHAR,p_pick_task_id,0::NUMERIC,0::NUMERIC,
            format('Cannot pick %s; task only has %s remaining.',p_qty_picked,v_task_remaining)::TEXT;
        RETURN;
    END IF;

    SELECT * INTO v_alloc FROM core.ALLOCATION WHERE ALLOCATION_ID=v_task.ALLOCATION_ID FOR UPDATE;
    v_alloc_remaining := v_alloc.QTY_ALLOCATED-v_alloc.QTY_PICKED-v_alloc.QTY_RELEASED;
    IF p_qty_picked > v_alloc_remaining THEN
        RETURN QUERY SELECT 'ERROR'::VARCHAR,p_pick_task_id,0::NUMERIC,0::NUMERIC,
            'Pick exceeds the open allocation quantity.'::TEXT;
        RETURN;
    END IF;

    SELECT * INTO v_inv FROM core.INVENTORY WHERE KEY=v_task.INVENTORY_KEY FOR UPDATE;
    IF p_qty_picked > v_inv.QTY_ON_HAND THEN
        RETURN QUERY SELECT 'ERROR'::VARCHAR,p_pick_task_id,0::NUMERIC,0::NUMERIC,'Pick exceeds physical stock on hand.'::TEXT;
        RETURN;
    END IF;
    IF p_qty_picked > v_inv.QTY_ALLOCATED THEN
        RETURN QUERY SELECT 'ERROR'::VARCHAR,p_pick_task_id,0::NUMERIC,0::NUMERIC,'Pick exceeds inventory reserved quantity.'::TEXT;
        RETURN;
    END IF;

    IF p_qty_picked > 0 THEN
        UPDATE core.INVENTORY
        SET QTY_ON_HAND=QTY_ON_HAND-p_qty_picked,
            QTY_ALLOCATED=QTY_ALLOCATED-p_qty_picked,
            MOVE_DSTAMP=now()
        WHERE KEY=v_task.INVENTORY_KEY;

        UPDATE core.ALLOCATION
        SET QTY_PICKED=QTY_PICKED+p_qty_picked,
            STATUS='PART_PICKED',LAST_UPDATE_DSTAMP=now(),LAST_UPDATED_BY=v_user
        WHERE ALLOCATION_ID=v_task.ALLOCATION_ID;

        UPDATE core.ORDER_LINE
        SET QTY_PICKED=COALESCE(QTY_PICKED,0)+p_qty_picked,
            QTY_SOFT_ALLOCATED=GREATEST(0,COALESCE(QTY_SOFT_ALLOCATED,0)-p_qty_picked),
            LAST_UPDATED_BY=v_user,LAST_UPDATE_DATE=now()
        WHERE CLIENT_ID=v_task.CLIENT_ID AND ORDER_ID=v_task.ORDER_ID AND LINE_ID=v_task.LINE_ID;

        INSERT INTO core.INVENTORY_TRANSACTION (
            CODE,SITE_ID,FROM_SITE_ID,FROM_LOC_ID,FINAL_LOC_ID,OWNER_ID,CLIENT_ID,SKU_ID,TAG_ID,
            CONTAINER_ID,BATCH_ID,QC_STATUS,EXPIRY_DSTAMP,MANUF_DSTAMP,ORIGIN_ID,CONDITION_ID,LOCK_STATUS,
            DSTAMP,SUPPLIER_ID,REFERENCE_ID,LINE_ID,STATION_ID,USER_ID,UPDATE_QTY,ORIGINAL_QTY,
            COMPLETE_DSTAMP,NOTES,LOCK_CODE,SOURCE,REFERENCE_TYPE
        ) VALUES (
            'PICK',v_inv.SITE_ID,v_inv.SITE_ID,v_inv.LOCATION_ID,v_inv.LOCATION_ID,v_inv.OWNER_ID,
            v_inv.CLIENT_ID,v_inv.SKU_ID,v_inv.TAG_ID,v_inv.CONTAINER_ID,v_inv.BATCH_ID,v_inv.QC_STATUS,
            v_inv.EXPIRY_DSTAMP,v_inv.MANUF_DSTAMP,v_inv.ORIGIN_ID,v_inv.CONDITION_ID,v_inv.LOCK_STATUS,
            now(),v_inv.SUPPLIER_ID,v_task.ORDER_ID,v_task.LINE_ID,v_station,v_user,-p_qty_picked,
            v_inv.QTY_ON_HAND,now(),format('Pick task %s',p_pick_task_id),v_inv.LOCK_CODE,
            'WAREHOUSE_EXECUTION','ORDER'
        );
    END IF;

    IF p_short_close THEN
        v_short := v_task_remaining-p_qty_picked;
        IF v_short > 0 THEN
            UPDATE core.INVENTORY SET QTY_ALLOCATED=GREATEST(0,QTY_ALLOCATED-v_short)
            WHERE KEY=v_task.INVENTORY_KEY;
            UPDATE core.ALLOCATION
            SET QTY_RELEASED=QTY_RELEASED+v_short,
                LAST_UPDATE_DSTAMP=now(),LAST_UPDATED_BY=v_user
            WHERE ALLOCATION_ID=v_task.ALLOCATION_ID;
            UPDATE core.ORDER_LINE
            SET QTY_SOFT_ALLOCATED=GREATEST(0,COALESCE(QTY_SOFT_ALLOCATED,0)-v_short),
                LAST_UPDATED_BY=v_user,LAST_UPDATE_DATE=now()
            WHERE CLIENT_ID=v_task.CLIENT_ID AND ORDER_ID=v_task.ORDER_ID AND LINE_ID=v_task.LINE_ID;
        END IF;
    END IF;

    UPDATE core.PICK_TASK
    SET QTY_PICKED=QTY_PICKED+p_qty_picked,
        SHORT_QTY=SHORT_QTY+v_short,
        STATUS=CASE
            WHEN p_short_close AND v_short>0 THEN 'SHORT'
            WHEN QTY_PICKED+p_qty_picked >= QTY_REQUIRED THEN 'PICKED'
            ELSE 'PART_PICKED' END,
        SHORT_REASON=CASE WHEN p_short_close AND v_short>0 THEN COALESCE(p_short_reason,'Short pick') ELSE SHORT_REASON END,
        STARTED_DSTAMP=COALESCE(STARTED_DSTAMP,now()),
        COMPLETED_DSTAMP=CASE WHEN (p_short_close AND v_short>0) OR QTY_PICKED+p_qty_picked>=QTY_REQUIRED THEN now() ELSE COMPLETED_DSTAMP END,
        LAST_UPDATE_DSTAMP=now(),LAST_UPDATED_BY=v_user
    WHERE PICK_TASK_ID=p_pick_task_id;

    UPDATE core.ALLOCATION
    SET STATUS=CASE
            WHEN QTY_PICKED+QTY_RELEASED >= QTY_ALLOCATED AND QTY_RELEASED>0 AND QTY_PICKED>0 THEN 'SHORT'
            WHEN QTY_PICKED >= QTY_ALLOCATED THEN 'PICKED'
            WHEN QTY_PICKED+QTY_RELEASED >= QTY_ALLOCATED THEN 'RELEASED'
            ELSE 'PART_PICKED' END,
        LAST_UPDATE_DSTAMP=now(),LAST_UPDATED_BY=v_user
    WHERE ALLOCATION_ID=v_task.ALLOCATION_ID;

    UPDATE core.ORDER_LINE ol
    SET QTY_TASKED=COALESCE(ol.QTY_PICKED,0)+COALESCE((
            SELECT SUM(GREATEST(0,pt.QTY_REQUIRED-pt.QTY_PICKED-pt.SHORT_QTY))
            FROM core.PICK_TASK pt
            WHERE pt.CLIENT_ID=ol.CLIENT_ID AND pt.ORDER_ID=ol.ORDER_ID AND pt.LINE_ID=ol.LINE_ID
              AND pt.STATUS IN ('OPEN','PART_PICKED')
        ),0),
        BACK_ORDERED=CASE WHEN COALESCE(ol.QTY_PICKED,0)+COALESCE(ol.QTY_SOFT_ALLOCATED,0)>=ol.QTY_ORDERED THEN 'N' ELSE 'Y' END,
        LAST_UPDATED_BY=v_user,LAST_UPDATE_DATE=now()
    WHERE ol.CLIENT_ID=v_task.CLIENT_ID AND ol.ORDER_ID=v_task.ORDER_ID AND ol.LINE_ID=v_task.LINE_ID;

    UPDATE core.ORDER_HEADER oh
    SET FULFILMENT_STATUS=CASE
            WHEN NOT EXISTS (SELECT 1 FROM core.ORDER_LINE ol WHERE ol.CLIENT_ID=v_task.CLIENT_ID AND ol.ORDER_ID=v_task.ORDER_ID AND COALESCE(ol.QTY_PICKED,0)<ol.QTY_ORDERED)
                THEN 'READY_TO_PACK'
            WHEN EXISTS (SELECT 1 FROM core.ORDER_LINE ol WHERE ol.CLIENT_ID=v_task.CLIENT_ID AND ol.ORDER_ID=v_task.ORDER_ID AND COALESCE(ol.QTY_PICKED,0)>0)
                THEN 'PART_PICKED'
            ELSE 'PICKING' END,
        LAST_UPDATED_BY=v_user,LAST_UPDATE_DATE=now()
    WHERE oh.CLIENT_ID=v_task.CLIENT_ID AND oh.ORDER_ID=v_task.ORDER_ID;

    RETURN QUERY SELECT
        CASE WHEN p_short_close AND v_short>0 THEN 'SHORT' WHEN p_qty_picked=v_task_remaining THEN 'PICKED' ELSE 'PART_PICKED' END::VARCHAR,
        p_pick_task_id,p_qty_picked::NUMERIC,v_short::NUMERIC,
        format('Confirmed %s unit(s) on pick task %s%s.',p_qty_picked,p_pick_task_id,
               CASE WHEN v_short>0 THEN format('; released %s short unit(s)',v_short) ELSE '' END)::TEXT;
END;
$$;
