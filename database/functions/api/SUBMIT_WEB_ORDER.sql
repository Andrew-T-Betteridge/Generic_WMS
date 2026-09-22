\set ON_ERROR_STOP on

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
    v_standard_fulfilment_method VARCHAR(30);
    v_livestock_fulfilment_method VARCHAR(30);
    v_delivery_distance_miles NUMERIC(8,2);
    v_carrier_id VARCHAR(50);
    v_carrier_service_level VARCHAR(50);
    v_result RECORD;
    v_existing interface.ORDER_HEADER_IF%ROWTYPE;
    v_existing_order core.ORDER_HEADER%ROWTYPE;
    v_item RECORD;
    v_line_id INTEGER := 0;
    v_discount NUMERIC(12,3) := 0;
    v_promo_code VARCHAR(50);
    v_free_delivery BOOLEAN := FALSE;
    v_idempotent_replay BOOLEAN := FALSE;

    v_customer_name TEXT;
    v_email TEXT;
    v_phone_raw TEXT;
    v_mobile_raw TEXT;
    v_phone TEXT;
    v_mobile TEXT;
    v_address1 TEXT;
    v_address2 TEXT;
    v_town TEXT;
    v_county TEXT;
    v_postcode_raw TEXT;
    v_postcode TEXT;
    v_country_raw TEXT;
    v_country TEXT;
    v_requires_delivery_address BOOLEAN := FALSE;
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
            'fulfilmentOptionCode',COALESCE(v_existing_order.FULFILMENT_OPTION_CODE,v_existing_order.SERVICE_LEVEL),
            'carrierId',v_existing_order.CARRIER_ID,
            'serviceLevel',v_existing_order.SERVICE_LEVEL,
            'fulfilmentMethod',v_existing_order.DISPATCH_METHOD,
            'promoCode',v_existing_order.PROMO_CODE,
            'freightCost',v_existing_order.FREIGHT_COST,
            'freeDelivery',COALESCE(v_existing_order.FREE_DELIVERY,'N')='Y',
            'orderValue',v_existing_order.ORDER_VALUE,
            'idempotentReplay',TRUE
        );
    END IF;

    --------------------------------------------------------------------------
    -- AUTHORITATIVE CUSTOMER VALIDATION
    --------------------------------------------------------------------------
    v_customer_name := NULLIF(
        regexp_replace(
            TRIM(COALESCE(p_payload#>>'{customer,name}','')),
            '[[:space:]]+',
            ' ',
            'g'
        ),
        ''
    );

    IF v_customer_name IS NULL THEN
        RETURN jsonb_build_object(
            'status','REJECTED',
            'code','CUSTOMER_NAME_REQUIRED'
        );
    END IF;

    IF LENGTH(v_customer_name) > 50 THEN
        RETURN jsonb_build_object(
            'status','REJECTED',
            'code','CUSTOMER_NAME_INVALID'
        );
    END IF;

    v_email := LOWER(NULLIF(TRIM(p_payload#>>'{customer,email}'),''));

    IF v_email IS NULL
       OR LENGTH(v_email) > 254
       OR v_email !~* '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$'
    THEN
        RETURN jsonb_build_object(
            'status','REJECTED',
            'code','CUSTOMER_EMAIL_INVALID'
        );
    END IF;

    v_phone_raw := NULLIF(TRIM(p_payload#>>'{customer,phone}'),'');
    v_mobile_raw := NULLIF(TRIM(p_payload#>>'{customer,mobile}'),'');

    IF v_phone_raw IS NULL AND v_mobile_raw IS NULL THEN
        RETURN jsonb_build_object(
            'status','REJECTED',
            'code','CUSTOMER_PHONE_INVALID'
        );
    END IF;

    IF v_phone_raw IS NOT NULL THEN
        v_phone := api.NORMALIZE_GB_PHONE(v_phone_raw);

        IF v_phone IS NULL THEN
            RETURN jsonb_build_object(
                'status','REJECTED',
                'code','CUSTOMER_PHONE_INVALID'
            );
        END IF;
    END IF;

    IF v_mobile_raw IS NOT NULL THEN
        v_mobile := api.NORMALIZE_GB_PHONE(v_mobile_raw);

        IF v_mobile IS NULL THEN
            RETURN jsonb_build_object(
                'status','REJECTED',
                'code','CUSTOMER_PHONE_INVALID'
            );
        END IF;
    END IF;

    IF v_phone IS NOT NULL
       AND v_mobile IS NOT NULL
       AND v_phone <> v_mobile
    THEN
        RETURN jsonb_build_object(
            'status','REJECTED',
            'code','CUSTOMER_PHONE_CONFLICT'
        );
    END IF;

    -- New storefront contract: customer.phone is canonical.
    -- customer.mobile remains accepted for backwards compatibility.
    v_phone := COALESCE(v_phone,v_mobile);

    --------------------------------------------------------------------------
    -- CANONICAL DELIVERY ADDRESS VALUES
    --------------------------------------------------------------------------
    v_address1 := NULLIF(
        regexp_replace(
            TRIM(COALESCE(p_payload#>>'{deliveryAddress,address1}','')),
            '[[:space:]]+',
            ' ',
            'g'
        ),
        ''
    );

    v_address2 := NULLIF(
        regexp_replace(
            TRIM(COALESCE(p_payload#>>'{deliveryAddress,address2}','')),
            '[[:space:]]+',
            ' ',
            'g'
        ),
        ''
    );

    v_town := NULLIF(
        regexp_replace(
            TRIM(COALESCE(p_payload#>>'{deliveryAddress,town}','')),
            '[[:space:]]+',
            ' ',
            'g'
        ),
        ''
    );

    v_county := NULLIF(
        regexp_replace(
            TRIM(COALESCE(p_payload#>>'{deliveryAddress,county}','')),
            '[[:space:]]+',
            ' ',
            'g'
        ),
        ''
    );

    v_postcode_raw := NULLIF(
        TRIM(p_payload#>>'{deliveryAddress,postcode}'),
        ''
    );

    v_country_raw := NULLIF(
        UPPER(TRIM(p_payload#>>'{deliveryAddress,country}')),
        ''
    );

    v_country := CASE
        WHEN v_country_raw IS NULL THEN 'GB'
        WHEN v_country_raw IN ('GB','GBR','UK','UNITED KINGDOM') THEN 'GB'
        ELSE v_country_raw
    END;

    IF v_country <> 'GB' THEN
        RETURN jsonb_build_object(
            'status','REJECTED',
            'code','DELIVERY_COUNTRY_UNSUPPORTED'
        );
    END IF;

    IF v_postcode_raw IS NOT NULL THEN
        v_postcode := api.NORMALIZE_GB_POSTCODE(v_postcode_raw);

        IF v_postcode IS NULL THEN
            RETURN jsonb_build_object(
                'status','REJECTED',
                'code','DELIVERY_POSTCODE_INVALID'
            );
        END IF;
    END IF;

    --------------------------------------------------------------------------
    -- AUTHORITATIVE ADDRESS STORAGE-LENGTH VALIDATION
    --------------------------------------------------------------------------
    -- Validate normalised values before quoting/order creation. Never silently
    -- truncate customer delivery data to fit core.ADDRESS.
    IF v_address1 IS NOT NULL AND LENGTH(v_address1) > 60 THEN
        RETURN jsonb_build_object(
            'status','REJECTED',
            'code','DELIVERY_ADDRESS1_TOO_LONG'
        );
    END IF;

    IF v_address2 IS NOT NULL AND LENGTH(v_address2) > 60 THEN
        RETURN jsonb_build_object(
            'status','REJECTED',
            'code','DELIVERY_ADDRESS2_TOO_LONG'
        );
    END IF;

    IF v_town IS NOT NULL AND LENGTH(v_town) > 60 THEN
        RETURN jsonb_build_object(
            'status','REJECTED',
            'code','DELIVERY_TOWN_TOO_LONG'
        );
    END IF;

    IF v_county IS NOT NULL AND LENGTH(v_county) > 60 THEN
        RETURN jsonb_build_object(
            'status','REJECTED',
            'code','DELIVERY_COUNTY_TOO_LONG'
        );
    END IF;
    /*
     * Quote against canonical customer/address values. Browser formatting is
     * never authoritative.
     */
    p_payload := jsonb_set(
        p_payload,
        '{customer,name}',
        to_jsonb(v_customer_name),
        TRUE
    );

    p_payload := jsonb_set(
        p_payload,
        '{customer,email}',
        to_jsonb(v_email),
        TRUE
    );

    p_payload := jsonb_set(
        p_payload,
        '{customer,phone}',
        to_jsonb(v_phone),
        TRUE
    );

    IF v_mobile_raw IS NOT NULL THEN
        p_payload := jsonb_set(
            p_payload,
            '{customer,mobile}',
            to_jsonb(COALESCE(v_mobile,v_phone)),
            TRUE
        );
    END IF;

    IF NOT (p_payload ? 'deliveryAddress') THEN
        p_payload := jsonb_set(
            p_payload,
            '{deliveryAddress}',
            '{}'::jsonb,
            TRUE
        );
    END IF;

    p_payload := jsonb_set(
        p_payload,
        '{deliveryAddress,country}',
        to_jsonb(v_country),
        TRUE
    );

    IF v_postcode IS NOT NULL THEN
        p_payload := jsonb_set(
            p_payload,
            '{deliveryAddress,postcode}',
            to_jsonb(v_postcode),
            TRUE
        );
    END IF;

    IF v_address1 IS NOT NULL THEN
        p_payload := jsonb_set(
            p_payload,
            '{deliveryAddress,address1}',
            to_jsonb(v_address1),
            TRUE
        );
    END IF;

    IF v_address2 IS NOT NULL THEN
        p_payload := jsonb_set(
            p_payload,
            '{deliveryAddress,address2}',
            to_jsonb(v_address2),
            TRUE
        );
    END IF;

    IF v_town IS NOT NULL THEN
        p_payload := jsonb_set(
            p_payload,
            '{deliveryAddress,town}',
            to_jsonb(v_town),
            TRUE
        );
    END IF;

    IF v_county IS NOT NULL THEN
        p_payload := jsonb_set(
            p_payload,
            '{deliveryAddress,county}',
            to_jsonb(v_county),
            TRUE
        );
    END IF;

    --------------------------------------------------------------------------
    -- FINAL FULFILMENT / PRICE REVALIDATION
    --------------------------------------------------------------------------
    v_quote := api.QUOTE_CHECKOUT(p_client_id,p_payload);
    v_basket := v_quote->'basket';

    IF NOT COALESCE((v_quote->>'valid')::BOOLEAN,FALSE) THEN
        IF COALESCE(v_quote->>'code','') = 'FULFILMENT_OPTION_NOT_AVAILABLE' THEN
            RETURN jsonb_build_object(
                'status','REJECTED',
                'code','FULFILMENT_ADDRESS_CHANGED',
                'quote',v_quote
            );
        END IF;

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

    v_standard_fulfilment_method :=
        NULLIF(
            UPPER(TRIM(v_selected#>>'{fulfilmentPlan,standardMethod}')),
            ''
        );

    v_livestock_fulfilment_method :=
        NULLIF(
            UPPER(TRIM(v_selected#>>'{fulfilmentPlan,livestockMethod}')),
            ''
        );

    v_delivery_distance_miles :=
        NULLIF(v_selected->>'distanceMiles','')::NUMERIC;

    v_carrier_id :=
        NULLIF(TRIM(v_selected->>'carrierId'),'');

    v_carrier_service_level :=
        NULLIF(TRIM(v_selected->>'serviceLevel'),'');

    v_requires_delivery_address :=
        v_fulfilment_method IN (
            'CARRIER',
            'LOCAL_DELIVERY',
            'ROUTE_DELIVERY',
            'MEET_POINT'
        );

    IF v_requires_delivery_address THEN
        IF v_address1 IS NULL THEN
            RETURN jsonb_build_object(
                'status','REJECTED',
                'code','DELIVERY_ADDRESS1_REQUIRED'
            );
        END IF;

        IF v_town IS NULL THEN
            RETURN jsonb_build_object(
                'status','REJECTED',
                'code','DELIVERY_TOWN_REQUIRED'
            );
        END IF;

        IF v_postcode IS NULL THEN
            RETURN jsonb_build_object(
                'status','REJECTED',
                'code','DELIVERY_POSTCODE_INVALID'
            );
        END IF;
    END IF;

    v_fulfilment_preference := COALESCE(
        NULLIF(
            UPPER(TRIM(v_selected->>'fulfilmentPreference')),
            ''
        ),
        NULLIF(
            UPPER(TRIM(p_payload->>'fulfilmentPreference')),
            ''
        ),
        'CONSOLIDATE'
    );

    IF v_fulfilment_preference NOT IN (
        'CONSOLIDATE',
        'SPLIT_WHEN_REQUIRED'
    ) THEN
        RAISE EXCEPTION 'INVALID_FULFILMENT_PREFERENCE';
    END IF;

    IF v_fulfilment_method NOT IN (
        'CARRIER',
        'LOCAL_DELIVERY',
        'COLLECTION',
        'ROUTE_DELIVERY',
        'MEET_POINT'
    ) THEN
        RAISE EXCEPTION 'INVALID_FULFILMENT_METHOD';
    END IF;

    --------------------------------------------------------------------------
    -- EXISTING ORDER CREATION PATH
    --------------------------------------------------------------------------
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
            CLIENT_ID,
            ADDRESS_ID,
            ADDRESS_TYPE,
            CONTACT,
            CONTACT_PHONE,
            CONTACT_MOBILE,
            CONTACT_EMAIL,
            NAME,
            ADDRESS1,
            ADDRESS2,
            TOWN,
            COUNTY,
            POSTCODE,
            COUNTRY,
            ACTIVE,
            DEFAULT_BILLING,
            DEFAULT_DELIVERY
        )
        VALUES (
            p_client_id,
            v_address_id,
            'DELIVERY',
            LEFT(v_customer_name,25),
            LEFT(v_phone,25),
            LEFT(
                CASE
                    WHEN v_mobile_raw IS NOT NULL
                        THEN COALESCE(v_mobile,v_phone)
                END,
                25
            ),
            v_email,
            LEFT(
                COALESCE(
                    NULLIF(TRIM(p_payload#>>'{deliveryAddress,name}'),''),
                    v_customer_name
                ),
                50
            ),
            v_address1,
            v_address2,
            v_town,
            v_county,
            LEFT(v_postcode,20),
            LEFT(v_country,25),
            'Y',
            'N',
            'Y'
        );

        INSERT INTO interface.ORDER_HEADER_IF (
            CLIENT_ID,
            SOURCE_SYSTEM,
            SOURCE_ORDER_ID,
            CUSTOMER_ID,
            ORDER_DATE,
            DISPATCH_METHOD,
            SERVICE_LEVEL,
            ADDRESS_ID,
            ORDER_VALUE,
            CURRENCY,
            FULFILMENT_PREFERENCE,
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
                INTERFACE_ID,
                LINE_ID,
                SOURCE_LINE_ID,
                SKU_ID,
                QTY_ORDERED,
                PRODUCT_PRICE,
                EXTENDED_PRICE,
                NOTES,
                PROCESS_STATUS
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
           FULFILMENT_OPTION_CODE=v_fulfilment_option_code,
           CARRIER_ID=v_carrier_id,
           SERVICE_LEVEL=v_carrier_service_level,
           FULFILMENT_PREFERENCE=v_fulfilment_preference,
           DELIVERY_DISTANCE_MILES=v_delivery_distance_miles,
           FREIGHT_COST=v_freight_cost,
           FREE_DELIVERY=CASE WHEN v_free_delivery THEN 'Y' ELSE 'N' END,
           ORDER_VALUE=v_order_value,
           PROMO_CODE=v_promo_code,
           LAST_UPDATED_BY='WEB_API',
           LAST_UPDATE_DATE=now()
     WHERE CLIENT_ID=p_client_id
       AND ORDER_ID=v_order_id;

    UPDATE core.ORDER_LINE ol
       SET FULFILMENT_TYPE =
           CASE
               WHEN UPPER(COALESCE(p.DELIVERY_CLASS,'STANDARD')) = 'LIVESTOCK'
                   THEN v_livestock_fulfilment_method
               ELSE v_standard_fulfilment_method
           END,
           LAST_UPDATED_BY='WEB_API',
           LAST_UPDATE_DATE=now()
      FROM core.PRODUCT_VARIANT pv
      JOIN core.PRODUCT p
        ON p.CLIENT_ID=pv.CLIENT_ID
       AND p.PRODUCT_ID=pv.PRODUCT_ID
     WHERE ol.CLIENT_ID=p_client_id
       AND ol.ORDER_ID=v_order_id
       AND pv.CLIENT_ID=ol.CLIENT_ID
       AND pv.SKU_ID=ol.SKU_ID
       AND pv.ACTIVE=TRUE;
    RETURN jsonb_build_object(
        'status','ACCEPTED',
        'interfaceId',v_interface_id,
        'orderId',v_order_id,
        'paymentStatus','PENDING',
        'fulfilmentStatus','NEW',
        'fulfilmentOptionCode',v_fulfilment_option_code,
        'fulfilmentMethod',v_fulfilment_method,
        'fulfilmentPreference',v_fulfilment_preference,
        'fulfilmentPlan',v_selected->'fulfilmentPlan',
        'deliveryDistanceMiles',v_delivery_distance_miles,
        'carrierId',v_carrier_id,
        'serviceLevel',v_carrier_service_level,
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
