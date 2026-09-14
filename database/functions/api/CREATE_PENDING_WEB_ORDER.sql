CREATE OR REPLACE FUNCTION api.CREATE_PENDING_WEB_ORDER(
    p_client_id VARCHAR,
    p_payload JSONB,
    p_account_id UUID DEFAULT NULL,
    p_payment_timeout_minutes INTEGER DEFAULT 30
)
RETURNS JSONB
LANGUAGE plpgsql
AS $$
DECLARE
    v_result JSONB;
    v_alloc RECORD;
    v_order_id VARCHAR(20);
    v_email VARCHAR(254);
BEGIN
    v_result := api.SUBMIT_WEB_ORDER(p_client_id,p_payload);

    IF v_result->>'status'<>'ACCEPTED' THEN
        RETURN v_result;
    END IF;

    v_order_id := v_result->>'orderId';
    v_email := LOWER(NULLIF(TRIM(p_payload#>>'{customer,email}'),''));

    IF p_account_id IS NOT NULL THEN
        IF NOT api.CLAIM_ORDER_ACCOUNT(p_client_id,v_order_id,p_account_id,v_email) THEN
            RAISE EXCEPTION 'ORDER_ACCOUNT_CLAIM_FAILED';
        END IF;
    END IF;

    SELECT * INTO v_alloc FROM core.ALLOCATE_ORDER(p_client_id,v_order_id);

    IF v_alloc.RESULT_STATUS NOT IN ('ALLOCATED','ALREADY_ALLOCATED') THEN
        RAISE EXCEPTION 'ORDER_STOCK_RESERVATION_FAILED: %',v_alloc.RESULT_MESSAGE;
    END IF;

    UPDATE core.ORDER_HEADER
       SET STATUS='PENDING_PAYMENT',
           PAYMENT_STATUS='PENDING',
           FULFILMENT_STATUS='RESERVED',
           PAYMENT_DUE_DSTAMP=now() + make_interval(mins=>GREATEST(COALESCE(p_payment_timeout_minutes,30),5)),
           LAST_UPDATED_BY='WEB_API',
           LAST_UPDATE_DATE=now()
     WHERE CLIENT_ID=p_client_id AND ORDER_ID=v_order_id;

    RETURN v_result || jsonb_build_object(
        'status','PENDING_PAYMENT',
        'paymentStatus','PENDING',
        'fulfilmentStatus','RESERVED',
        'stockReserved',TRUE,
        'paymentDueAt',(
            SELECT PAYMENT_DUE_DSTAMP FROM core.ORDER_HEADER
            WHERE CLIENT_ID=p_client_id AND ORDER_ID=v_order_id
        )
    );
END;
$$;
