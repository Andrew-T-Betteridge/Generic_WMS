CREATE OR REPLACE FUNCTION api.CREATE_CUSTOMER_INTEREST(p_client_id VARCHAR,p_payload JSONB)
RETURNS JSONB LANGUAGE plpgsql AS $$
DECLARE v_id UUID; v_product_id VARCHAR; v_sku_id VARCHAR; v_type VARCHAR; v_email TEXT;
BEGIN
 v_type:=UPPER(COALESCE(NULLIF(TRIM(p_payload->>'interestType'),''),'WAITLIST'));
 v_product_id:=NULLIF(TRIM(p_payload->>'productId'),'');
 v_sku_id:=NULLIF(TRIM(p_payload->>'skuId'),'');
 v_email:=LOWER(NULLIF(TRIM(p_payload->>'email'),''));
 IF v_type NOT IN ('WAITLIST','GROWING_STOCK') THEN RAISE EXCEPTION 'INVALID_INTEREST_TYPE'; END IF;
 IF v_product_id IS NULL OR v_email IS NULL OR position('@' in v_email)<2 THEN RAISE EXCEPTION 'PRODUCT_AND_VALID_EMAIL_REQUIRED'; END IF;
 IF NOT EXISTS(SELECT 1 FROM core.PRODUCT WHERE CLIENT_ID=p_client_id AND PRODUCT_ID=v_product_id AND ACTIVE=TRUE) THEN RAISE EXCEPTION 'PRODUCT_NOT_FOUND'; END IF;
 INSERT INTO core.CUSTOMER_INTEREST(CLIENT_ID,INTEREST_TYPE,PRODUCT_ID,SKU_ID,REQUESTED_QTY,CONTACT_NAME,EMAIL,PHONE,PREFERRED_CHANNEL,CONSENT_TO_NOTIFY)
 VALUES(p_client_id,v_type,v_product_id,v_sku_id,NULLIF(p_payload->>'requestedQty','')::numeric,NULLIF(TRIM(p_payload->>'name'),''),v_email,
        NULLIF(TRIM(p_payload->>'phone'),''),UPPER(COALESCE(NULLIF(TRIM(p_payload->>'preferredChannel'),''),'EMAIL')),
        COALESCE((p_payload->>'consentToNotify')::boolean,TRUE)) RETURNING INTEREST_ID INTO v_id;
 RETURN jsonb_build_object('interestId',v_id,'status','ACTIVE','interestType',v_type);
END; $$;
