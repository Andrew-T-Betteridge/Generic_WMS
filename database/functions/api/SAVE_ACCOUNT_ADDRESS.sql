CREATE OR REPLACE FUNCTION api.SAVE_ACCOUNT_ADDRESS(
    p_client_id VARCHAR,
    p_account_id UUID,
    p_payload JSONB
)
RETURNS JSONB
LANGUAGE plpgsql
AS $$
DECLARE
    v_address_id VARCHAR(15);
    v_default_delivery BOOLEAN := COALESCE((p_payload->>'defaultDelivery')::BOOLEAN,FALSE);
    v_default_billing BOOLEAN := COALESCE((p_payload->>'defaultBilling')::BOOLEAN,FALSE);
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM core.CUSTOMER_ACCOUNT
        WHERE CLIENT_ID=p_client_id AND ACCOUNT_ID=p_account_id AND ACTIVE=TRUE
    ) THEN
        RAISE EXCEPTION 'ACCOUNT_NOT_FOUND';
    END IF;

    IF NULLIF(TRIM(p_payload->>'address1'),'') IS NULL
       OR NULLIF(TRIM(p_payload->>'town'),'') IS NULL
       OR NULLIF(TRIM(p_payload->>'postcode'),'') IS NULL THEN
        RAISE EXCEPTION 'ADDRESS_REQUIRED_FIELDS_MISSING';
    END IF;

    v_address_id := 'A' || UPPER(SUBSTRING(REPLACE(gen_random_uuid()::TEXT,'-','') FROM 1 FOR 14));

    INSERT INTO core.ADDRESS(
        CLIENT_ID,ADDRESS_ID,ADDRESS_TYPE,
        CONTACT,CONTACT_PHONE,CONTACT_MOBILE,CONTACT_EMAIL,
        NAME,ADDRESS1,ADDRESS2,TOWN,COUNTY,POSTCODE,COUNTRY,
        ACTIVE,DEFAULT_BILLING,DEFAULT_DELIVERY
    )
    SELECT
        p_client_id,v_address_id,'ACCOUNT',
        LEFT(NULLIF(TRIM(p_payload->>'contact'),''),25),
        LEFT(NULLIF(TRIM(p_payload->>'phone'),''),25),
        LEFT(NULLIF(TRIM(p_payload->>'mobile'),''),25),
        a.EMAIL,
        LEFT(NULLIF(TRIM(p_payload->>'name'),''),50),
        LEFT(TRIM(p_payload->>'address1'),60),
        LEFT(NULLIF(TRIM(p_payload->>'address2'),''),60),
        LEFT(TRIM(p_payload->>'town'),60),
        LEFT(NULLIF(TRIM(p_payload->>'county'),''),60),
        LEFT(UPPER(TRIM(p_payload->>'postcode')),20),
        LEFT(COALESCE(NULLIF(UPPER(TRIM(p_payload->>'country')),''),'GB'),25),
        'Y',
        CASE WHEN v_default_billing THEN 'Y' ELSE 'N' END,
        CASE WHEN v_default_delivery THEN 'Y' ELSE 'N' END
    FROM core.CUSTOMER_ACCOUNT a
    WHERE a.CLIENT_ID=p_client_id AND a.ACCOUNT_ID=p_account_id;

    IF v_default_delivery THEN
        UPDATE core.CUSTOMER_ACCOUNT_ADDRESS
           SET DEFAULT_DELIVERY=FALSE,LAST_UPDATE_DSTAMP=now()
         WHERE ACCOUNT_ID=p_account_id;
    END IF;

    IF v_default_billing THEN
        UPDATE core.CUSTOMER_ACCOUNT_ADDRESS
           SET DEFAULT_BILLING=FALSE,LAST_UPDATE_DSTAMP=now()
         WHERE ACCOUNT_ID=p_account_id;
    END IF;

    INSERT INTO core.CUSTOMER_ACCOUNT_ADDRESS(
        ACCOUNT_ID,CLIENT_ID,ADDRESS_ID,ADDRESS_LABEL,DEFAULT_DELIVERY,DEFAULT_BILLING
    )
    VALUES(
        p_account_id,p_client_id,v_address_id,
        LEFT(NULLIF(TRIM(p_payload->>'label'),''),50),
        v_default_delivery,v_default_billing
    );

    RETURN jsonb_build_object('addressId',v_address_id,'saved',TRUE);
END;
$$;
