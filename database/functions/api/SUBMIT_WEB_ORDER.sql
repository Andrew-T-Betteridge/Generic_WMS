CREATE OR REPLACE FUNCTION api.SUBMIT_WEB_ORDER (
    p_client_id VARCHAR,
    p_payload JSONB
)
RETURNS JSONB
LANGUAGE plpgsql
AS $$
DECLARE
    v_quote JSONB;
    v_basket JSONB;
    v_selected JSONB;
    v_interface_id UUID;
    v_source_order_id VARCHAR(100);
    v_order_id VARCHAR(20);
    v_address_id VARCHAR(15);
    v_customer_id VARCHAR(15);
    v_currency VARCHAR(3);
    v_order_value NUMERIC(12,3);
    v_freight_cost NUMERIC(12,3);
    v_total_before_delivery NUMERIC(12,3);
    v_fulfilment_preference VARCHAR(30);
    v_fulfilment_method VARCHAR(30);
    v_fulfilment_option_code VARCHAR(100);
    v_result RECORD;
    v_existing interface.ORDER_HEADER_IF%ROWTYPE;
    v_existing_order core.ORDER_HEADER%ROWTYPE;
    v_item RECORD;
    v_line_id INTEGER := 0;
    v_discount NUMERIC(12,3) := 0;
    v_promo_code VARCHAR(50);
    v_free_delivery BOOLEAN := FALSE;
    v_idempotent_replay BOOLEAN := FALSE;
BEGIN
    v_source_order_id := NULLIF(TRIM(p_payload->>'idempotencyKey'),'');
    IF v_source_order_id IS NULL THEN
        RAISE EXCEPTION 'IDEMPOTENCY_KEY_REQUIRED';
    END IF;

    v_fulfilment_option_code :=
        NULLIF(TRIM(p_payload->>'fulfilmentOptionCode'),'');
    IF v_fulfilment_option_code IS NULL THEN
        RETURN jsonb_build_object(
            'status','REJECTED',
            'code','FULFILMENT_OPTION_REQUIRED'
        );
    END IF;

    SELECT *
      INTO v_existing
      FROM interface.ORDER_HEADER_IF
     WHERE CLIENT_ID=p_client_id
       AND SOURCE_SYSTEM='WEBSITE'
       AND SOURCE_ORDER_ID=v_source_order_id;

    IF FOUND AND v_existing.PROCESS_STATUS='PROCESSED' THEN
        v_idempotent_replay := TRUE;

        SELECT *
          INTO v_existing_order
          FROM core.ORDER_HEADER
         WHERE CLIENT_ID=p_client_id
           AND ORDER_ID=v_existing.ORDER_ID;

        RETURN jsonb_build_object(
            'status','ACCEPTED',
            'interfaceId',v_existing.INTERFACE_ID,
            'orderId',v_existing.ORDER_ID,
            'paymentStatus',v_existing_order.PAYMENT_STATUS,
            'fulfilmentStatus',v_existing_order.FULFILMENT_STATUS,
            'fulfilmentOptionCode',v_existing_order.SERVICE_LEVEL,
            'fulfilmentMethod',v_existing_order.DISPATCH_METHOD,
            'promoCode',v_existing_order.PROMO_CODE,
            'freightCost',v_existing_order.FREIGHT_COST,
            'freeDelivery',COALESCE(v_existing_order.FREE_DELIVERY,'N')='Y',
            'orderValue',v_existing_order.ORDER_VALUE,
            'idempotentReplay',TRUE
        );
    END IF;

    v_quote := api.QUOTE_CHECKOUT(p_client_id,p_payload);
    v_basket := v_quote->'basket';

    IF NOT COALESCE((v_quote->>'valid')::BOOLEAN,FALSE) THEN
        RETURN jsonb_build_object(
            'status','REJECTED',
            'code',
                CASE
                    WHEN NOT COALESCE((v_basket->>'valid')::BOOLEAN,FALSE)
                        THEN 'BASKET_INVALID'
                    ELSE COALESCE(v_quote->>'code','CHECKOUT_INVALID')
                END,
            'quote',v_quote
        );
    END IF;

    v_selected := v_quote->'selectedFulfilmentOption';

    IF v_selected IS NULL THEN
        RETURN jsonb_build_object(
            'status','REJECTED',
            'code','FULFILMENT_OPTION_NOT_AVAILABLE',
            'quote',v_quote
        );
    END IF;

    IF NOT COALESCE((v_quote->>'paymentReady')::BOOLEAN,FALSE) THEN
        RETURN jsonb_build_object(
            'status','REJECTED',
            'code','FULFILMENT_PRICE_PENDING',
            'selectedFulfilmentOption',v_selected,
            'quote',v_quote
        );
    END IF;

    v_currency := COALESCE(v_basket->>'currency','GBP');
    v_discount := COALESCE((v_quote->>'discountAmount')::NUMERIC,0);
    v_total_before_delivery :=
        COALESCE((v_quote->>'totalBeforeDelivery')::NUMERIC,0);
    v_freight_cost := COALESCE((v_quote->>'freightCost')::NUMERIC,0);
    v_order_value := COALESCE((v_quote->>'total')::NUMERIC,0);
    v_promo_code := NULLIF(UPPER(TRIM(p_payload->>'promoCode')),'');
    v_free_delivery := COALESCE((v_quote->>'freeDelivery')::BOOLEAN,FALSE);

    v_fulfilment_method :=
        UPPER(NULLIF(TRIM(v_selected->>'fulfilmentMethod'),''));
    v_fulfilment_option_code :=
        NULLIF(TRIM(v_selected->>'code'),'');

    v_fulfilment_preference := COALESCE(
        NULLIF(UPPER(TRIM(p_payload->>'fulfilmentPreference')),''),
        'CONSOLIDATE'
    );

    IF v_fulfilment_preference NOT IN ('CONSOLIDATE','SPLIT_WHEN_REQUIRED') THEN
        RAISE EXCEPTION 'INVALID_FULFILMENT_PREFERENCE';
    END IF;

    IF v_fulfilment_method NOT IN (
        'CARRIER','LOCAL_DELIVERY','COLLECTION','ROUTE_DELIVERY','MEET_POINT'
    ) THEN
        RAISE EXCEPTION 'INVALID_FULFILMENT_METHOD';
    END IF;

    IF v_existing.INTERFACE_ID IS NOT NULL THEN
        v_idempotent_replay := TRUE;

        SELECT *
          INTO v_result
          FROM interface.PROCESS_ORDER_INTERFACE(v_existing.INTERFACE_ID);

        IF v_result.RESULT_STATUS<>'PROCESSED' THEN
            RETURN jsonb_build_object(
                'status','ERROR',
                'interfaceId',v_existing.INTERFACE_ID,
                'orderId',v_result.RESULT_ORDER_ID,
                'message',v_result.RESULT_MESSAGE,
                'idempotentReplay',TRUE
            );
        END IF;

        v_order_id := v_result.RESULT_ORDER_ID;
        v_interface_id := v_existing.INTERFACE_ID;
    ELSE
        v_customer_id := LEFT(
            COALESCE(
                NULLIF(TRIM(p_payload#>>'{customer,customerId}'),''),
                'WEB-' || UPPER(
                    SUBSTRING(
                        REPLACE(gen_random_uuid()::TEXT,'-','')
                        FROM 1 FOR 11
                    )
                )
            ),
            15
        );

        v_address_id :=
            'W' || UPPER(
                SUBSTRING(
                    REPLACE(gen_random_uuid()::TEXT,'-','')
                    FROM 1 FOR 14
                )
            );

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
            LEFT(
                COALESCE(
                    NULLIF(TRIM(p_payload#>>'{deliveryAddress,name}'),''),
                    NULLIF(TRIM(p_payload#>>'{customer,name}'),'')
                ),
                50
            ),
            LEFT(NULLIF(TRIM(p_payload#>>'{deliveryAddress,address1}'),''),60),
            LEFT(NULLIF(TRIM(p_payload#>>'{deliveryAddress,address2}'),''),60),
            LEFT(NULLIF(TRIM(p_payload#>>'{deliveryAddress,town}'),''),60),
            LEFT(NULLIF(TRIM(p_payload#>>'{deliveryAddress,county}'),''),60),
            LEFT(NULLIF(UPPER(TRIM(p_payload#>>'{deliveryAddress,postcode}')),''),20),
            LEFT(
                COALESCE(
                    NULLIF(UPPER(TRIM(p_payload#>>'{deliveryAddress,country}')),''),
                    'GB'
                ),
                25
            ),
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
            v_fulfilment_option_code,
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
    END IF;

    UPDATE core.ORDER_HEADER
       SET DISPATCH_METHOD=v_fulfilment_method,
           SERVICE_LEVEL=v_fulfilment_option_code,
           FULFILMENT_PREFERENCE=v_fulfilment_preference,
           FREIGHT_COST=v_freight_cost,
           FREE_DELIVERY=CASE WHEN v_free_delivery THEN 'Y' ELSE 'N' END,
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
        'fulfilmentOptionCode',v_fulfilment_option_code,
        'fulfilmentMethod',v_fulfilment_method,
        'promoCode',v_promo_code,
        'discountAmount',v_discount,
        'totalBeforeDelivery',v_total_before_delivery,
        'freightCost',v_freight_cost,
        'freeDelivery',v_free_delivery,
        'orderValue',v_order_value,
        'idempotentReplay',v_idempotent_replay
    );
END;
$$;
