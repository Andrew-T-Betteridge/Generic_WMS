CREATE OR REPLACE FUNCTION api.SET_PAYMENT_PROVIDER_REFERENCE(
    p_client_id VARCHAR,p_payment_id UUID,p_provider_reference VARCHAR,p_provider_status VARCHAR
)
RETURNS JSONB
LANGUAGE plpgsql
AS $$
DECLARE v_payment core.PAYMENT_TRANSACTION%ROWTYPE;
BEGIN
    UPDATE core.PAYMENT_TRANSACTION
       SET PROVIDER_REFERENCE=p_provider_reference,
           PROVIDER_STATUS=p_provider_status,
           STATUS=CASE WHEN STATUS='CREATED' THEN 'PENDING' ELSE STATUS END,
           LAST_UPDATE_DSTAMP=now()
     WHERE CLIENT_ID=p_client_id AND PAYMENT_ID=p_payment_id
     RETURNING * INTO v_payment;

    IF NOT FOUND THEN RAISE EXCEPTION 'PAYMENT_NOT_FOUND'; END IF;

    RETURN jsonb_build_object(
        'paymentId',v_payment.PAYMENT_ID,
        'providerReference',v_payment.PROVIDER_REFERENCE,
        'status',v_payment.STATUS
    );
END;
$$;
