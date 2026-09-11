-- Allocation reserves stock; picking later converts the reservation into a
-- physical inventory change. Allocation history is retained permanently.
CREATE OR REPLACE FUNCTION core.ALLOCATE_ORDER (
    p_client_id VARCHAR,
    p_order_id  VARCHAR
)
RETURNS TABLE (
    RESULT_STATUS          VARCHAR,
    RESULT_ORDER_ID        VARCHAR,
    RESULT_LINES           INTEGER,
    RESULT_FULL_LINES      INTEGER,
    RESULT_PART_LINES      INTEGER,
    RESULT_NO_STOCK_LINES  INTEGER,
    RESULT_QTY_ALLOCATED   NUMERIC,
    RESULT_MESSAGE         TEXT
)
LANGUAGE plpgsql
AS $$
DECLARE
    v_line RECORD;
    v_inv RECORD;
    v_required NUMERIC(15,6);
    v_take NUMERIC(15,6);
    v_line_allocated NUMERIC(15,6);
    v_total_allocated NUMERIC(15,6) := 0;
    v_lines INTEGER := 0;
    v_full_lines INTEGER := 0;
    v_part_lines INTEGER := 0;
    v_no_stock_lines INTEGER := 0;
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM core.ORDER_HEADER
        WHERE CLIENT_ID = p_client_id AND ORDER_ID = p_order_id
    ) THEN
        RETURN QUERY SELECT 'ERROR'::VARCHAR, p_order_id::VARCHAR, 0,0,0,0,0::NUMERIC,
            'Order does not exist.'::TEXT;
        RETURN;
    END IF;

    FOR v_line IN
        SELECT ol.CLIENT_ID, ol.ORDER_ID, ol.LINE_ID, ol.SKU_ID,
               ol.BATCH_ID, ol.CONDITION_ID, ol.OWNER_ID,
               ol.QTY_ORDERED,
               COALESCE(ol.QTY_PICKED,0) AS QTY_PICKED,
               COALESCE(ol.QTY_SOFT_ALLOCATED,0) AS QTY_SOFT_ALLOCATED
        FROM core.ORDER_LINE ol
        WHERE ol.CLIENT_ID = p_client_id
          AND ol.ORDER_ID = p_order_id
          AND UPPER(COALESCE(ol.ALLOCATE,'Y')) <> 'N'
          AND COALESCE(ol.QTY_PICKED,0) + COALESCE(ol.QTY_SOFT_ALLOCATED,0) < ol.QTY_ORDERED
        ORDER BY ol.LINE_ID
        FOR UPDATE
    LOOP
        v_lines := v_lines + 1;
        v_required := v_line.QTY_ORDERED - v_line.QTY_PICKED - v_line.QTY_SOFT_ALLOCATED;
        v_line_allocated := 0;

        FOR v_inv IN
            SELECT i.KEY, (i.QTY_ON_HAND - i.QTY_ALLOCATED) AS AVAILABLE_QTY
            FROM core.INVENTORY i
            JOIN core.LOCATION l ON l.LOCATION_ID = i.LOCATION_ID
            WHERE i.CLIENT_ID = v_line.CLIENT_ID
              AND i.SKU_ID = v_line.SKU_ID
              AND (i.QTY_ON_HAND - i.QTY_ALLOCATED) > 0
              AND UPPER(COALESCE(i.DISALLOW_ALLOC,'N')) <> 'Y'
              AND UPPER(COALESCE(i.LOCK_STATUS,'')) NOT IN ('LOCKED','HOLD','QUARANTINE')
              AND UPPER(COALESCE(l.DISALLOW_ALLOC,'N')) <> 'Y'
              AND UPPER(COALESCE(l.LOCK_STATUS,'')) NOT IN ('LOCKED','HOLD','QUARANTINE')
              AND UPPER(COALESCE(l.ACTIVE,'Y')) = 'Y'
              AND (v_line.BATCH_ID IS NULL OR i.BATCH_ID = v_line.BATCH_ID)
              AND (v_line.CONDITION_ID IS NULL OR i.CONDITION_ID = v_line.CONDITION_ID)
              AND (v_line.OWNER_ID IS NULL OR i.OWNER_ID = v_line.OWNER_ID)
            ORDER BY i.RECEIPT_DSTAMP, i.KEY
            FOR UPDATE OF i SKIP LOCKED
        LOOP
            EXIT WHEN v_required <= 0;
            v_take := LEAST(v_required, v_inv.AVAILABLE_QTY);

            UPDATE core.INVENTORY
            SET QTY_ALLOCATED = QTY_ALLOCATED + v_take
            WHERE KEY = v_inv.KEY;

            INSERT INTO core.ALLOCATION (
                CLIENT_ID, ORDER_ID, LINE_ID, INVENTORY_KEY,
                QTY_ALLOCATED, QTY_PICKED, QTY_RELEASED, STATUS,
                CREATED_BY, LAST_UPDATED_BY
            ) VALUES (
                v_line.CLIENT_ID, v_line.ORDER_ID, v_line.LINE_ID, v_inv.KEY,
                v_take, 0, 0, 'ALLOCATED',
                'ALLOCATE_ORDER', 'ALLOCATE_ORDER'
            );

            v_required := v_required - v_take;
            v_line_allocated := v_line_allocated + v_take;
            v_total_allocated := v_total_allocated + v_take;
        END LOOP;

        UPDATE core.ORDER_LINE
        SET QTY_SOFT_ALLOCATED = COALESCE(QTY_SOFT_ALLOCATED,0) + v_line_allocated,
            BACK_ORDERED = CASE
                WHEN COALESCE(QTY_PICKED,0) + COALESCE(QTY_SOFT_ALLOCATED,0) + v_line_allocated >= QTY_ORDERED
                    THEN 'N' ELSE 'Y' END,
            LAST_UPDATED_BY = 'ALLOCATE_ORDER', LAST_UPDATE_DATE = now()
        WHERE CLIENT_ID = v_line.CLIENT_ID AND ORDER_ID = v_line.ORDER_ID AND LINE_ID = v_line.LINE_ID;

        IF v_line_allocated = 0 THEN v_no_stock_lines := v_no_stock_lines + 1;
        ELSIF v_required > 0 THEN v_part_lines := v_part_lines + 1;
        ELSE v_full_lines := v_full_lines + 1;
        END IF;
    END LOOP;

    UPDATE core.ORDER_HEADER oh
    SET FULFILMENT_STATUS = CASE
            WHEN NOT EXISTS (
                SELECT 1 FROM core.ORDER_LINE ol
                WHERE ol.CLIENT_ID = p_client_id AND ol.ORDER_ID = p_order_id
                  AND COALESCE(ol.QTY_PICKED,0) + COALESCE(ol.QTY_SOFT_ALLOCATED,0) < ol.QTY_ORDERED
            ) THEN 'ALLOCATED'
            WHEN EXISTS (
                SELECT 1 FROM core.ORDER_LINE ol
                WHERE ol.CLIENT_ID = p_client_id AND ol.ORDER_ID = p_order_id
                  AND COALESCE(ol.QTY_SOFT_ALLOCATED,0) > 0
            ) THEN 'PART_ALLOCATED'
            ELSE COALESCE(oh.FULFILMENT_STATUS,'UNALLOCATED')
        END,
        LAST_UPDATED_BY = 'ALLOCATE_ORDER', LAST_UPDATE_DATE = now()
    WHERE oh.CLIENT_ID = p_client_id AND oh.ORDER_ID = p_order_id;

    IF v_lines = 0 THEN
        RETURN QUERY SELECT 'ALREADY_ALLOCATED'::VARCHAR, p_order_id::VARCHAR, 0,0,0,0,0::NUMERIC,
            'No order lines required additional allocation.'::TEXT;
        RETURN;
    END IF;

    RETURN QUERY SELECT
        CASE WHEN v_part_lines = 0 AND v_no_stock_lines = 0 THEN 'ALLOCATED'
             WHEN v_full_lines = 0 AND v_part_lines = 0 AND v_no_stock_lines > 0 THEN 'NO_STOCK'
             ELSE 'PART_ALLOCATED' END::VARCHAR,
        p_order_id::VARCHAR, v_lines, v_full_lines, v_part_lines, v_no_stock_lines,
        v_total_allocated::NUMERIC,
        format('Processed %s line(s): %s full, %s part, %s no stock. Reserved %s unit(s).',
               v_lines, v_full_lines, v_part_lines, v_no_stock_lines, v_total_allocated)::TEXT;
END;
$$;
