CREATE OR REPLACE FUNCTION api.PREPARE_PAYMENT(p_client_id VARCHAR,p_payload JSONB)
RETURNS JSONB LANGUAGE plpgsql AS $$
DECLARE v_id UUID; v_provider VARCHAR; v_key TEXT;
BEGIN
 v_provider:=UPPER(COALESCE(NULLIF(TRIM(p_payload->>'provider'),''),'STRIPE')); v_key:=NULLIF(TRIM(p_payload->>'idempotencyKey'),'');
 IF v_provider NOT IN ('STRIPE','PAYPAL') THEN RAISE EXCEPTION 'UNSUPPORTED_PAYMENT_PROVIDER'; END IF;
 IF COALESCE(NULLIF(p_payload->>'amount','')::numeric,0)<=0 OR NULLIF(TRIM(p_payload->>'referenceId'),'') IS NULL THEN RAISE EXCEPTION 'INVALID_PAYMENT_REQUEST'; END IF;
 IF v_key IS NOT NULL THEN SELECT PAYMENT_ID INTO v_id FROM core.PAYMENT_TRANSACTION WHERE CLIENT_ID=p_client_id AND PROVIDER=v_provider AND IDEMPOTENCY_KEY=v_key; END IF;
 IF v_id IS NULL THEN
   INSERT INTO core.PAYMENT_TRANSACTION(CLIENT_ID,PROVIDER,REFERENCE_TYPE,REFERENCE_ID,AMOUNT,CURRENCY,IDEMPOTENCY_KEY)
   VALUES(p_client_id,v_provider,UPPER(COALESCE(NULLIF(TRIM(p_payload->>'referenceType'),''),'ORDER')),TRIM(p_payload->>'referenceId'),(p_payload->>'amount')::numeric,UPPER(COALESCE(NULLIF(TRIM(p_payload->>'currency'),''),'GBP')),v_key)
   RETURNING PAYMENT_ID INTO v_id;
 END IF;
 RETURN jsonb_build_object('paymentId',v_id,'provider',v_provider,'status','CREATED','providerIntegrated',FALSE,'requiresProviderAction',TRUE);
END; $$;
