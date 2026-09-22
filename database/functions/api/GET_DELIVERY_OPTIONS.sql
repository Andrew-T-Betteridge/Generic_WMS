CREATE OR REPLACE FUNCTION api.GET_DELIVERY_OPTIONS(
    p_client_id VARCHAR,
    p_payload JSONB
)
RETURNS JSONB
LANGUAGE plpgsql
STABLE
AS $$
DECLARE
    v_basket JSONB;
    v_options JSONB := '[]'::jsonb;
    v_postcode TEXT;
    v_country TEXT;
    v_subtotal NUMERIC;
    v_has_standard BOOLEAN;
    v_has_livestock BOOLEAN;
    v_basket_type TEXT;
    v_distance JSONB;
    v_postcode_valid BOOLEAN := FALSE;
    v_distance_available BOOLEAN := FALSE;
    v_distance_miles NUMERIC;
    v_standard_method TEXT;
    v_livestock_method TEXT;
    v_preference TEXT;
    v_matched_zone_count INTEGER := 0;
    v_pricing_method TEXT;
    v_distance_price NUMERIC;
    v_carrier_quote JSONB;
    v_carrier_price NUMERIC;
    v_zone_price NUMERIC;
    v_requires_manual BOOLEAN;
    v_carrier_id TEXT;
    v_service_level TEXT;
    z RECORD;
BEGIN
    v_basket :=
        api.VALIDATE_BASKET(
            p_client_id,
            COALESCE(p_payload->'items','[]'::jsonb)
        );

    IF NOT COALESCE((v_basket->>'valid')::boolean,FALSE) THEN
        RETURN jsonb_build_object(
            'valid',FALSE,
            'basket',v_basket,
            'deliveryContext',jsonb_build_object(
                'postcodeValid',FALSE,
                'distanceAvailable',FALSE
            ),
            'fulfilmentOptions','[]'::jsonb
        );
    END IF;

    v_postcode :=
        regexp_replace(
            UPPER(COALESCE(p_payload#>>'{deliveryAddress,postcode}','')),
            '[[:space:]]',
            '',
            'g'
        );

    v_country :=
        UPPER(
            COALESCE(
                NULLIF(TRIM(p_payload#>>'{deliveryAddress,country}'),''),
                'GB'
            )
        );

    v_subtotal := COALESCE((v_basket->>'subtotal')::numeric,0);
    v_has_standard := COALESCE((v_basket->>'hasStandard')::boolean,FALSE);
    v_has_livestock := COALESCE((v_basket->>'hasLivestock')::boolean,FALSE);

    v_basket_type :=
        CASE
            WHEN v_has_standard AND v_has_livestock THEN 'MIXED'
            WHEN v_has_livestock THEN 'LIVESTOCK'
            ELSE 'STANDARD'
        END;

    IF v_country='GB' THEN
        v_distance := api.GET_POSTCODE_DISTANCE(p_client_id,v_postcode);

        v_postcode_valid :=
            COALESCE((v_distance->>'postcodeValid')::boolean,FALSE);

        v_distance_available :=
            COALESCE((v_distance->>'distanceAvailable')::boolean,FALSE);

        IF v_distance_available THEN
            v_distance_miles :=
                NULLIF(v_distance->>'distanceMiles','')::numeric;
        END IF;
    ELSE
        v_distance :=
            jsonb_build_object(
                'postcodeValid',FALSE,
                'distanceAvailable',FALSE,
                'code','DELIVERY_COUNTRY_UNSUPPORTED'
            );
    END IF;

    v_options :=
        v_options ||
        jsonb_build_array(
            jsonb_build_object(
                'code','COLLECTION',
                'label','Collection',
                'optionDescription','Collect your order from FINatics Aquatics.',
                'fulfilmentMethod','COLLECTION',
                'fulfilmentPreference','CONSOLIDATE',
                'basketType',v_basket_type,
                'carrierId',NULL,
                'serviceLevel',NULL,
                'pricingMethod','FIXED',
                'price',0,
                'priceComponents',
                    jsonb_build_object(
                        'localDelivery',0,
                        'carrier',0
                    ),
                'currency',v_basket->>'currency',
                'requiresManualConfirmation',FALSE,
                'fulfilmentPlan',
                    jsonb_build_object(
                        'standardMethod',
                            CASE WHEN v_has_standard THEN 'COLLECTION' ELSE NULL END,
                        'livestockMethod',
                            CASE WHEN v_has_livestock THEN 'COLLECTION' ELSE NULL END
                    )
            )
        );

    IF v_postcode_valid THEN
        FOR z IN
            SELECT *
            FROM config.DELIVERY_ZONE dz
            WHERE dz.CLIENT_ID=p_client_id
              AND dz.ACTIVE=TRUE
              AND UPPER(dz.COUNTRY)=v_country
              AND (
                    UPPER(COALESCE(dz.BASKET_TYPE,'ANY'))='ANY'
                    OR UPPER(dz.BASKET_TYPE)=v_basket_type
                  )
              AND (
                    dz.POSTCODE_PREFIX IS NULL
                    OR v_postcode LIKE
                       regexp_replace(
                           UPPER(dz.POSTCODE_PREFIX),
                           '[[:space:]]',
                           '',
                           'g'
                       ) || '%'
                  )
              AND (
                    dz.MIN_ORDER_VALUE IS NULL
                    OR v_subtotal>=dz.MIN_ORDER_VALUE
                  )
              AND (
                    dz.MIN_DISTANCE_MILES IS NULL
                    OR (
                        v_distance_available
                        AND v_distance_miles>=dz.MIN_DISTANCE_MILES
                    )
                  )
              AND (
                    dz.MAX_DISTANCE_MILES IS NULL
                    OR (
                        v_distance_available
                        AND v_distance_miles<dz.MAX_DISTANCE_MILES
                    )
                  )
            ORDER BY dz.PRIORITY,dz.ZONE_ID
        LOOP
            v_matched_zone_count := v_matched_zone_count + 1;

            v_standard_method :=
                CASE
                    WHEN v_has_standard THEN
                        UPPER(
                            COALESCE(
                                NULLIF(TRIM(z.STANDARD_FULFILMENT_METHOD),''),
                                z.FULFILMENT_METHOD
                            )
                        )
                    ELSE NULL
                END;

            v_livestock_method :=
                CASE
                    WHEN v_has_livestock THEN
                        UPPER(
                            COALESCE(
                                NULLIF(TRIM(z.LIVESTOCK_FULFILMENT_METHOD),''),
                                z.FULFILMENT_METHOD
                            )
                        )
                    ELSE NULL
                END;

            v_preference :=
                CASE
                    WHEN v_has_standard
                         AND v_has_livestock
                         AND v_standard_method IS DISTINCT FROM v_livestock_method
                    THEN 'SPLIT_WHEN_REQUIRED'
                    ELSE 'CONSOLIDATE'
                END;

            v_pricing_method :=
                UPPER(COALESCE(NULLIF(TRIM(z.PRICING_METHOD),''),'FIXED'));

            v_distance_price := NULL;
            v_carrier_quote := NULL;
            v_carrier_price := NULL;
            v_zone_price := NULL;
            v_requires_manual := z.REQUIRES_MANUAL_CONFIRMATION;
            v_carrier_id := z.CARRIER_ID;
            v_service_level := z.SERVICE_LEVEL;

            IF v_pricing_method IN ('DISTANCE','DISTANCE_PLUS_CARRIER') THEN
                IF v_distance_available
                   AND z.DISTANCE_RATE_PER_MILE IS NOT NULL
                THEN
                    v_distance_price :=
                        ROUND(
                            (
                                v_distance_miles*z.DISTANCE_RATE_PER_MILE
                            )::numeric,
                            2
                        );

                    IF z.MINIMUM_DELIVERY_PRICE IS NOT NULL THEN
                        v_distance_price :=
                            GREATEST(
                                v_distance_price,
                                z.MINIMUM_DELIVERY_PRICE
                            );
                    END IF;
                ELSE
                    v_requires_manual := TRUE;
                END IF;
            END IF;

            IF v_pricing_method IN ('CARRIER','DISTANCE_PLUS_CARRIER') THEN
                v_carrier_quote :=
                    api.QUOTE_CARRIER_SERVICE(
                        p_client_id,
                        v_basket,
                        v_country,
                        v_postcode,
                        z.CARRIER_ID,
                        z.SERVICE_LEVEL
                    );

                IF COALESCE((v_carrier_quote->>'quoted')::boolean,FALSE) THEN
                    v_carrier_price :=
                        NULLIF(v_carrier_quote->>'price','')::numeric;
                    v_carrier_id :=
                        COALESCE(v_carrier_quote->>'carrierId',v_carrier_id);
                    v_service_level :=
                        COALESCE(v_carrier_quote->>'serviceLevel',v_service_level);

                    IF COALESCE(
                           (v_carrier_quote->>'requiresManualConfirmation')::boolean,
                           FALSE
                       )
                    THEN
                        v_requires_manual := TRUE;
                    END IF;
                ELSE
                    v_requires_manual := TRUE;
                END IF;
            END IF;

            v_zone_price :=
                CASE v_pricing_method
                    WHEN 'FIXED' THEN z.DELIVERY_PRICE
                    WHEN 'DISTANCE' THEN v_distance_price
                    WHEN 'CARRIER' THEN v_carrier_price
                    WHEN 'DISTANCE_PLUS_CARRIER' THEN
                        CASE
                            WHEN v_distance_price IS NULL
                                 OR v_carrier_price IS NULL
                            THEN NULL
                            ELSE ROUND((v_distance_price+v_carrier_price)::numeric,2)
                        END
                    ELSE NULL
                END;

            IF v_zone_price IS NULL THEN
                v_requires_manual := TRUE;
            END IF;

            v_options :=
                v_options ||
                jsonb_build_array(
                    jsonb_build_object(
                        'code',z.ZONE_ID,
                        'label',z.ZONE_NAME,
                        'optionDescription',z.OPTION_DESCRIPTION,
                        'fulfilmentMethod',z.FULFILMENT_METHOD,
                        'fulfilmentPreference',v_preference,
                        'basketType',v_basket_type,
                        'carrierId',v_carrier_id,
                        'serviceLevel',v_service_level,
                        'pricingMethod',v_pricing_method,
                        'price',v_zone_price,
                        'priceComponents',
                            jsonb_build_object(
                                'localDelivery',v_distance_price,
                                'carrier',v_carrier_price
                            ),
                        'currency',z.CURRENCY,
                        'requiresManualConfirmation',v_requires_manual,
                        'distanceMiles',v_distance_miles,
                        'shippingWeightKg',
                            NULLIF(v_basket->>'standardWeightKg','')::numeric,
                        'shippingDataComplete',
                            COALESCE(
                                (v_basket->>'standardShippingDataComplete')::boolean,
                                TRUE
                            ),
                        'carrierQuote',v_carrier_quote,
                        'fulfilmentPlan',
                            jsonb_build_object(
                                'standardMethod',v_standard_method,
                                'livestockMethod',v_livestock_method
                            )
                    )
                );
        END LOOP;
    END IF;

    IF v_postcode_valid AND v_matched_zone_count=0 THEN
        IF v_basket_type='STANDARD' THEN
            v_options :=
                v_options ||
                jsonb_build_array(
                    jsonb_build_object(
                        'code','STANDARD_CARRIER',
                        'label','Delivery',
                        'optionDescription','Delivery price requires confirmation.',
                        'fulfilmentMethod','CARRIER',
                        'fulfilmentPreference','CONSOLIDATE',
                        'basketType',v_basket_type,
                        'carrierId',NULL,
                        'serviceLevel',NULL,
                        'pricingMethod','MANUAL',
                        'price',NULL,
                        'currency',v_basket->>'currency',
                        'requiresManualConfirmation',TRUE,
                        'fulfilmentPlan',
                            jsonb_build_object(
                                'standardMethod','CARRIER',
                                'livestockMethod',NULL
                            )
                    )
                );
        ELSIF v_basket_type='LIVESTOCK' THEN
            v_options :=
                v_options ||
                jsonb_build_array(
                    jsonb_build_object(
                        'code','MEET_POINT',
                        'label','Meet halfway / arranged handover',
                        'optionDescription','The handover location and price require confirmation.',
                        'fulfilmentMethod','MEET_POINT',
                        'fulfilmentPreference','CONSOLIDATE',
                        'basketType',v_basket_type,
                        'carrierId',NULL,
                        'serviceLevel',NULL,
                        'pricingMethod','MANUAL',
                        'price',NULL,
                        'currency',v_basket->>'currency',
                        'requiresManualConfirmation',TRUE,
                        'fulfilmentPlan',
                            jsonb_build_object(
                                'standardMethod',NULL,
                                'livestockMethod','MEET_POINT'
                            )
                    )
                );
        ELSE
            v_options :=
                v_options ||
                jsonb_build_array(
                    jsonb_build_object(
                        'code','MIXED_DELIVERY_MANUAL',
                        'label','Arrange delivery',
                        'optionDescription','This mixed fish and product order requires a delivery arrangement.',
                        'fulfilmentMethod','LOCAL_DELIVERY',
                        'fulfilmentPreference','CONSOLIDATE',
                        'basketType',v_basket_type,
                        'carrierId',NULL,
                        'serviceLevel',NULL,
                        'pricingMethod','MANUAL',
                        'price',NULL,
                        'currency',v_basket->>'currency',
                        'requiresManualConfirmation',TRUE,
                        'fulfilmentPlan',
                            jsonb_build_object(
                                'standardMethod','LOCAL_DELIVERY',
                                'livestockMethod','LOCAL_DELIVERY'
                            )
                    )
                );
        END IF;
    END IF;

    RETURN jsonb_build_object(
        'valid',TRUE,
        'basket',v_basket,
        'deliveryContext',
            jsonb_build_object(
                'basketType',v_basket_type,
                'country',v_country,
                'postcode',COALESCE(v_distance->>'postcode',v_postcode),
                'postcodeValid',v_postcode_valid,
                'distanceAvailable',v_distance_available,
                'distanceMiles',v_distance_miles,
                'distanceBasis',v_distance->>'distanceBasis',
                'statusCode',v_distance->>'code',
                'standardWeightKg',
                    NULLIF(v_basket->>'standardWeightKg','')::numeric,
                'standardShippingDataComplete',
                    COALESCE(
                        (v_basket->>'standardShippingDataComplete')::boolean,
                        TRUE
                    )
            ),
        'fulfilmentOptions',v_options
    );
END;
$$;