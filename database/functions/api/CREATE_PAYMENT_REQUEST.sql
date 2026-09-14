CREATE OR REPLACE FUNCTION api.CREATE_PAYMENT_REQUEST(
    p_client_id VARCHAR,
    p_account_id UUID,
    p_reference_type VARCHAR,
    p_reference_id VARCHAR,
    p_provider VARCHAR,
    p_idempotency_key VARCHAR
)
RETURNS JSONB
LANGUAGE plpgsql
AS $$
DECLARE
    v_type VARCHAR(30) := UPPER(TRIM(p_reference_type));
    v_provider VARCHAR(30) := UPPER(COALESCE(NULLIF(TRIM(p_provider),''),'STRIPE'));
    v_amount NUMERIC(12,2);
    v_currency VARCHAR(3);
    v_payment core.PAYMENT_TRANSACTION%ROWTYPE;
BEGIN
    IF v_provider NOT IN ('STRIPE','PAYPAL') THEN
        RAISE EXCEPTION 'UNSUPPORTED_PAYMENT_PROVIDER';
    END IF;

    IF NULLIF(TRIM(p_idempotency_key),'') IS NULL THEN
        RAISE EXCEPTION 'IDEMPOTENCY_KEY_REQUIRED';
    END IF;

    IF v_type='ORDER' THEN
        SELECT ORDER_VALUE::NUMERIC(12,2),COALESCE(INV_CURRENCY,'GBP')
          INTO v_amount,v_currency
          FROM core.ORDER_HEADER
         WHERE CLIENT_ID=p_client_id
           AND ORDER_ID=p_reference_id
           AND (p_account_id IS NULL OR ACCOUNT_ID=p_account_id);

        IF NOT FOUND THEN RAISE EXCEPTION 'ORDER_NOT_FOUND_OR_NOT_OWNED'; END IF;
    ELSIF v_type='RESERVATION' THEN
        SELECT COALESCE(SUM(l.QTY_RESERVED*l.UNIT_PRICE),0)::NUMERIC(12,2),'GBP'
          INTO v_amount,v_currency
          FROM core.STOCK_RESERVATION r
          JOIN core.STOCK_RESERVATION_LINE l ON l.RESERVATION_ID=r.RESERVATION_ID
         WHERE r.CLIENT_ID=p_client_id
           AND r.RESERVATION_ID=p_reference_id::UUID
           AND r.STATUS='ACTIVE'
           AND (p_account_id IS NULL OR r.ACCOUNT_ID=p_account_id)
         GROUP BY r.RESERVATION_ID;

        IF NOT FOUND THEN RAISE EXCEPTION 'RESERVATION_NOT_FOUND_OR_NOT_OWNED'; END IF;
    ELSE
        RAISE EXCEPTION 'UNSUPPORTED_PAYMENT_REFERENCE';
    END IF;

    IF COALESCE(v_amount,0)<=0 THEN RAISE EXCEPTION 'PAYMENT_AMOUNT_NOT_POSITIVE'; END IF;

    SELECT * INTO v_payment
      FROM core.PAYMENT_TRANSACTION
     WHERE CLIENT_ID=p_client_id
       AND PROVIDER=v_provider
       AND IDEMPOTENCY_KEY=p_idempotency_key;

    IF NOT FOUND THEN
        INSERT INTO core.PAYMENT_TRANSACTION(
            CLIENT_ID,ACCOUNT_ID,PROVIDER,REFERENCE_TYPE,REFERENCE_ID,
            AMOUNT,CURRENCY,STATUS,IDEMPOTENCY_KEY
        )
        VALUES(
            p_client_id,p_account_id,v_provider,v_type,p_reference_id,
            v_amount,v_currency,'CREATED',p_idempotency_key
        )
        RETURNING * INTO v_payment;
    END IF;

    RETURN jsonb_build_object(
        'paymentId',v_payment.PAYMENT_ID,
        'provider',v_payment.PROVIDER,
        'referenceType',v_payment.REFERENCE_TYPE,
        'referenceId',v_payment.REFERENCE_ID,
        'amount',v_payment.AMOUNT,
        'currency',v_payment.CURRENCY,
        'status',v_payment.STATUS,
        'providerReference',v_payment.PROVIDER_REFERENCE,
        'idempotentReplay',v_payment.CREATED_DSTAMP<>v_payment.LAST_UPDATE_DSTAMP
    );
END;
$$;
