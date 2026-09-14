CREATE OR REPLACE FUNCTION api.SUBMIT_WEB_ORDER (
    p_client_id VARCHAR,
    p_payload JSONB
)
RETURNS JSONB
LANGUAGE plpgsql
AS $$
DECLARE
    v_validation JSONB;
    v_interface_id UUID;
    v_source_order_id VARCHAR(100);
    v_order_id VARCHAR(20);
    v_address_id VARCHAR(15);
    v_customer_id VARCHAR(15);
    v_currency VARCHAR(3);
    v_order_value NUMERIC(12,3);
    v_fulfilment_preference VARCHAR(30);
    v_fulfilment_method VARCHAR(30);
    v_result RECORD;
    v_existing interface.ORDER_HEADER_IF%ROWTYPE;
    v_item RECORD;
    v_line_id INTEGER := 0;
    v_promotion JSONB;
    v_discount NUMERIC(12,3) := 0;
    v_promo_code VARCHAR(50);
BEGIN
    v_source_order_id := NULLIF(TRIM(p_payload->>'idempotencyKey'),'');
    IF v_source_order_id IS NULL THEN
        RAISE EXCEPTION 'IDEMPOTENCY_KEY_REQUIRED';
    END IF;

    v_validation := api.VALIDATE_BASKET(
        p_client_id,
        COALESCE(p_payload->'items','[]'::jsonb)
    );

    IF NOT COALESCE((v_validation->>'valid')::BOOLEAN,FALSE) THEN
        RETURN jsonb_build_object(
            'status','REJECTED',
            'code','BASKET_INVALID',
            'validation',v_validation
        );
    END IF;

    v_currency := COALESCE(v_validation->>'currency','GBP');
    v_order_value := COALESCE((v_validation->>'subtotal')::NUMERIC,0);
    v_promo_code := NULLIF(UPPER(TRIM(p_payload->>'promoCode')),'');
    IF v_promo_code IS NOT NULL THEN
        v_promotion := api.VALIDATE_PROMOTION(p_client_id,v_promo_code,v_order_value,NULL);
        IF NOT COALESCE((v_promotion->>'valid')::BOOLEAN,FALSE) THEN
            RETURN jsonb_build_object('status','REJECTED','code','PROMOTION_INVALID','promotion',v_promotion);
        END IF;
        v_discount := COALESCE((v_promotion->>'discountAmount')::NUMERIC,0);
        v_order_value := GREATEST(v_order_value-v_discount,0);
    END IF;
    v_fulfilment_preference := COALESCE(
        NULLIF(UPPER(TRIM(p_payload->>'fulfilmentPreference')),''),
        'CONSOLIDATE'
    );
    v_fulfilment_method := COALESCE(
        NULLIF(UPPER(TRIM(p_payload->>'fulfilmentMethod')),''),
        'CARRIER'
    );

    IF v_fulfilment_preference NOT IN ('CONSOLIDATE','SPLIT_WHEN_REQUIRED') THEN
        RAISE EXCEPTION 'INVALID_FULFILMENT_PREFERENCE';
    END IF;

    IF v_fulfilment_method NOT IN (
        'CARRIER','LOCAL_DELIVERY','COLLECTION','ROUTE_DELIVERY','MEET_POINT'
    ) THEN
        RAISE EXCEPTION 'INVALID_FULFILMENT_METHOD';
    END IF;

    -- Idempotency: return the existing interface/core order for an exact retry.
    SELECT *
      INTO v_existing
      FROM interface.ORDER_HEADER_IF
     WHERE CLIENT_ID=p_client_id
       AND SOURCE_SYSTEM='WEBSITE'
       AND SOURCE_ORDER_ID=v_source_order_id;

    IF FOUND THEN
        IF v_existing.PROCESS_STATUS='PROCESSED' THEN
            RETURN jsonb_build_object(
                'status','ACCEPTED',
                'interfaceId',v_existing.INTERFACE_ID,
                'orderId',v_existing.ORDER_ID,
                'idempotentReplay',TRUE
            );
        END IF;

        SELECT *
          INTO v_result
          FROM interface.PROCESS_ORDER_INTERFACE(v_existing.INTERFACE_ID);

        RETURN jsonb_build_object(
            'status',
                CASE WHEN v_result.RESULT_STATUS='PROCESSED'
                     THEN 'ACCEPTED' ELSE 'ERROR' END,
            'interfaceId',v_existing.INTERFACE_ID,
            'orderId',v_result.RESULT_ORDER_ID,
            'message',v_result.RESULT_MESSAGE,
            'idempotentReplay',TRUE
        );
    END IF;

    v_customer_id := LEFT(
        COALESCE(
            NULLIF(TRIM(p_payload#>>'{customer,customerId}'),''),
            'WEB-' || UPPER(SUBSTRING(REPLACE(gen_random_uuid()::TEXT,'-','') FROM 1 FOR 11))
        ),
        15
    );

    -- ADDRESS_ID is deliberately short because the existing core model is VARCHAR(15).
    v_address_id := 'W' || UPPER(SUBSTRING(REPLACE(gen_random_uuid()::TEXT,'-','') FROM 1 FOR 14));

    INSERT INTO core.ADDRESS (
        CLIENT_ID,ADDRESS_ID,ADDRESS_TYPE,
        CONTACT,CONTACT_PHONE,CONTACT_MOBILE,CONTACT_EMAIL,
        NAME,ADDRESS1,ADDRESS2,TOWN,COUNTY,POSTCODE,COUNTRY,
        ACTIVE,DEFAULT_BILLING,DEFAULT_DELIVERY
    )
    VALUES (
        p_client_id,
        v_address_id,
        'DELIVERY',
        LEFT(NULLIF(TRIM(p_payload#>>'{customer,name}'),''),25),
        LEFT(NULLIF(TRIM(p_payload#>>'{customer,phone}'),''),25),
        LEFT(NULLIF(TRIM(p_payload#>>'{customer,mobile}'),''),25),
        NULLIF(TRIM(p_payload#>>'{customer,email}'),''),
        LEFT(COALESCE(
            NULLIF(TRIM(p_payload#>>'{deliveryAddress,name}'),''),
            NULLIF(TRIM(p_payload#>>'{customer,name}'),'')
        ),50),
        LEFT(NULLIF(TRIM(p_payload#>>'{deliveryAddress,address1}'),''),60),
        LEFT(NULLIF(TRIM(p_payload#>>'{deliveryAddress,address2}'),''),60),
        LEFT(NULLIF(TRIM(p_payload#>>'{deliveryAddress,town}'),''),60),
        LEFT(NULLIF(TRIM(p_payload#>>'{deliveryAddress,county}'),''),60),
        LEFT(NULLIF(UPPER(TRIM(p_payload#>>'{deliveryAddress,postcode}')),''),20),
        LEFT(COALESCE(
            NULLIF(UPPER(TRIM(p_payload#>>'{deliveryAddress,country}')),''),
            'GB'
        ),25),
        'Y','N','Y'
    );

    INSERT INTO interface.ORDER_HEADER_IF (
        CLIENT_ID,SOURCE_SYSTEM,SOURCE_ORDER_ID,
        CUSTOMER_ID,ORDER_DATE,
        DISPATCH_METHOD,SERVICE_LEVEL,ADDRESS_ID,
        ORDER_VALUE,CURRENCY,FULFILMENT_PREFERENCE,
        PROCESS_STATUS
    )
    VALUES (
        p_client_id,
        'WEBSITE',
        v_source_order_id,
        v_customer_id,
        now(),
        v_fulfilment_method,
        NULLIF(TRIM(p_payload->>'serviceLevel'),''),
        v_address_id,
        v_order_value,
        v_currency,
        v_fulfilment_preference,
        'NEW'
    )
    RETURNING INTERFACE_ID INTO v_interface_id;

    FOR v_item IN
        SELECT
            x.sku_id,
            x.qty,
            pv.WEB_PRICE,
            pv.VARIANT_NAME
        FROM jsonb_to_recordset(p_payload->'items')
             AS x(sku_id VARCHAR, qty NUMERIC)
        JOIN core.PRODUCT_VARIANT pv
          ON pv.CLIENT_ID=p_client_id
         AND pv.SKU_ID=x.sku_id
         AND pv.ACTIVE=TRUE
        ORDER BY x.sku_id
    LOOP
        v_line_id := v_line_id + 1;

        INSERT INTO interface.ORDER_LINE_IF (
            INTERFACE_ID,LINE_ID,SOURCE_LINE_ID,
            SKU_ID,QTY_ORDERED,PRODUCT_PRICE,EXTENDED_PRICE,
            NOTES,PROCESS_STATUS
        )
        VALUES (
            v_interface_id,
            v_line_id,
            v_line_id::TEXT,
            v_item.sku_id,
            v_item.qty,
            v_item.WEB_PRICE,
            v_item.WEB_PRICE*v_item.qty,
            LEFT(v_item.VARIANT_NAME,80),
            'NEW'
        );
    END LOOP;

    SELECT *
      INTO v_result
      FROM interface.PROCESS_ORDER_INTERFACE(v_interface_id);

    IF v_result.RESULT_STATUS<>'PROCESSED' THEN
        RETURN jsonb_build_object(
            'status','ERROR',
            'interfaceId',v_interface_id,
            'orderId',v_result.RESULT_ORDER_ID,
            'message',v_result.RESULT_MESSAGE
        );
    END IF;

    v_order_id := v_result.RESULT_ORDER_ID;

    -- Freight/payment remain pending until the relevant external provider is integrated.
    UPDATE core.ORDER_HEADER
       SET DISPATCH_METHOD=v_fulfilment_method,
           FULFILMENT_PREFERENCE=v_fulfilment_preference,
           ORDER_VALUE=v_order_value,
           PROMO_CODE=v_promo_code,
           LAST_UPDATED_BY='WEB_API',
           LAST_UPDATE_DATE=now()
     WHERE CLIENT_ID=p_client_id
       AND ORDER_ID=v_order_id;

    RETURN jsonb_build_object(
        'status','ACCEPTED',
        'interfaceId',v_interface_id,
        'orderId',v_order_id,
        'paymentStatus','PENDING',
        'fulfilmentStatus','NEW',
        'promoCode',v_promo_code,
        'discountAmount',v_discount,
        'orderValue',v_order_value,
        'idempotentReplay',FALSE
    );
END;
$$;
