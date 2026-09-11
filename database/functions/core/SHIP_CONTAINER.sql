-- Shipping changes fulfilment state only. Physical stock already left
-- INVENTORY at pick confirmation, so shipment must not reduce QTY_ON_HAND again.
CREATE OR REPLACE FUNCTION core.SHIP_CONTAINER (
    p_client_id VARCHAR,
    p_container_id VARCHAR,
    p_user_id VARCHAR DEFAULT 'SYSTEM',
    p_station_id VARCHAR DEFAULT 'WMS'
)
RETURNS TABLE (
    RESULT_STATUS VARCHAR,
    RESULT_CONTAINER_ID VARCHAR,
    RESULT_ORDER_ID VARCHAR,
    RESULT_QTY_SHIPPED NUMERIC,
    RESULT_MESSAGE TEXT
)
LANGUAGE plpgsql
AS $$
DECLARE
    v_container RECORD;
    v_line RECORD;
    v_total NUMERIC(15,6):=0;
    v_user VARCHAR(20):=LEFT(COALESCE(NULLIF(p_user_id,''),'SYSTEM'),20);
BEGIN
    SELECT * INTO v_container FROM core.ORDER_CONTAINER
    WHERE CLIENT_ID=p_client_id AND CONTAINER_ID=p_container_id FOR UPDATE;
    IF NOT FOUND THEN
        RETURN QUERY SELECT 'ERROR'::VARCHAR,p_container_id::VARCHAR,NULL::VARCHAR,0::NUMERIC,'Container does not exist.'::TEXT;
        RETURN;
    END IF;

    IF NOT EXISTS (SELECT 1 FROM core.SHIPPING_MANIFEST WHERE CLIENT_ID=p_client_id AND CONTAINER_ID=p_container_id AND SHIPPED='N') THEN
        RETURN QUERY SELECT 'ALREADY_SHIPPED'::VARCHAR,p_container_id::VARCHAR,v_container.ORDER_ID::VARCHAR,0::NUMERIC,
            'Container has no unshipped packed quantity.'::TEXT;
        RETURN;
    END IF;

    FOR v_line IN
        SELECT LINE_ID,SUM(COALESCE(QTY_PICKED,0)-COALESCE(QTY_SHIPPED,0)) AS QTY
        FROM core.SHIPPING_MANIFEST
        WHERE CLIENT_ID=p_client_id AND CONTAINER_ID=p_container_id AND SHIPPED='N'
        GROUP BY LINE_ID
        ORDER BY LINE_ID
    LOOP
        IF v_line.QTY>0 THEN
            UPDATE core.ORDER_LINE
            SET QTY_SHIPPED=COALESCE(QTY_SHIPPED,0)+v_line.QTY,
                LAST_UPDATED_BY=v_user,LAST_UPDATE_DATE=now()
            WHERE CLIENT_ID=p_client_id AND ORDER_ID=v_container.ORDER_ID AND LINE_ID=v_line.LINE_ID;
            v_total:=v_total+v_line.QTY;
        END IF;
    END LOOP;

    UPDATE core.SHIPPING_MANIFEST
    SET QTY_SHIPPED=QTY_PICKED,SHIPPED='Y',SHIPPED_DSTAMP=now(),STATUS='SHIPPED',USER_ID=v_user
    WHERE CLIENT_ID=p_client_id AND CONTAINER_ID=p_container_id AND SHIPPED='N';

    UPDATE core.ORDER_CONTAINER SET STATUS='SHIPPED' WHERE CLIENT_ID=p_client_id AND CONTAINER_ID=p_container_id;

    UPDATE core.ORDER_HEADER oh
    SET SHIPPED_DATE=CASE WHEN NOT EXISTS (
                SELECT 1 FROM core.ORDER_LINE ol WHERE ol.CLIENT_ID=p_client_id AND ol.ORDER_ID=v_container.ORDER_ID
                  AND COALESCE(ol.QTY_SHIPPED,0)<ol.QTY_ORDERED
            ) THEN now() ELSE oh.SHIPPED_DATE END,
        FULFILMENT_STATUS=CASE WHEN NOT EXISTS (
                SELECT 1 FROM core.ORDER_LINE ol WHERE ol.CLIENT_ID=p_client_id AND ol.ORDER_ID=v_container.ORDER_ID
                  AND COALESCE(ol.QTY_SHIPPED,0)<ol.QTY_ORDERED
            ) THEN 'SHIPPED' ELSE 'PART_SHIPPED' END,
        LAST_UPDATED_BY=v_user,LAST_UPDATE_DATE=now()
    WHERE oh.CLIENT_ID=p_client_id AND oh.ORDER_ID=v_container.ORDER_ID;

    RETURN QUERY SELECT 'SHIPPED'::VARCHAR,p_container_id::VARCHAR,v_container.ORDER_ID::VARCHAR,v_total::NUMERIC,
        format('Shipped container %s with %s unit(s).',p_container_id,v_total)::TEXT;
END;
$$;
