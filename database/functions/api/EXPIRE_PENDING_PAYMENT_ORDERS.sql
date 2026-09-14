CREATE OR REPLACE FUNCTION api.EXPIRE_PENDING_PAYMENT_ORDERS(
    p_client_id VARCHAR,
    p_limit INTEGER DEFAULT 100
)
RETURNS JSONB
LANGUAGE plpgsql
AS $$
DECLARE
    r RECORD;
    v_dealloc RECORD;
    v_expired INTEGER := 0;
BEGIN
    FOR r IN
        SELECT ORDER_ID
          FROM core.ORDER_HEADER
         WHERE CLIENT_ID=p_client_id
           AND STATUS='PENDING_PAYMENT'
           AND PAYMENT_STATUS NOT IN ('PAID','AUTHORISED')
           AND PAYMENT_DUE_DSTAMP IS NOT NULL
           AND PAYMENT_DUE_DSTAMP<=now()
         ORDER BY PAYMENT_DUE_DSTAMP
         LIMIT GREATEST(COALESCE(p_limit,100),1)
         FOR UPDATE SKIP LOCKED
    LOOP
        SELECT * INTO v_dealloc FROM core.DEALLOCATE_ORDER(p_client_id,r.ORDER_ID);

        UPDATE core.ORDER_HEADER
           SET STATUS='CANCELLED',
               PAYMENT_STATUS='CANCELLED',
               FULFILMENT_STATUS='CANCELLED',
               LAST_UPDATED_BY='PAYMENT_EXPIRY',
               LAST_UPDATE_DATE=now()
         WHERE CLIENT_ID=p_client_id AND ORDER_ID=r.ORDER_ID;

        v_expired := v_expired + 1;
    END LOOP;

    RETURN jsonb_build_object('expiredOrders',v_expired);
END;
$$;
