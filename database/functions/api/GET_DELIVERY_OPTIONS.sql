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

    v_subtotal :=
        COALESCE((v_basket->>'subtotal')::numeric,0);

    v_has_standard :=
        COALESCE((v_basket->>'hasStandard')::boolean,FALSE);

    v_has_livestock :=
        COALESCE((v_basket->>'hasLivestock')::boolean,FALSE);

    v_basket_type :=
        CASE
            WHEN v_has_standard AND v_has_livestock THEN 'MIXED'
            WHEN v_has_livestock THEN 'LIVESTOCK'
            ELSE 'STANDARD'
        END;

    IF v_country = 'GB' THEN
        v_distance :=
            api.GET_POSTCODE_DISTANCE(
                p_client_id,
                v_postcode
            );

        v_postcode_valid :=
            COALESCE(
                (v_distance->>'postcodeValid')::boolean,
                FALSE
            );

        v_distance_available :=
            COALESCE(
                (v_distance->>'distanceAvailable')::boolean,
                FALSE
            );

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

    --------------------------------------------------------------------------
    -- Collection is always available for a valid basket.
    --------------------------------------------------------------------------
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
                'price',0,
                'currency',v_basket->>'currency',
                'requiresManualConfirmation',FALSE,
                'fulfilmentPlan',
                    jsonb_build_object(
                        'standardMethod',
                            CASE WHEN v_has_standard
                                 THEN 'COLLECTION'
                                 ELSE NULL
                            END,
                        'livestockMethod',
                            CASE WHEN v_has_livestock
                                 THEN 'COLLECTION'
                                 ELSE NULL
                            END
                    )
            )
        );

    --------------------------------------------------------------------------
    -- Delivery options require a real GB postcode.
    --------------------------------------------------------------------------
    IF v_postcode_valid THEN
        FOR z IN
            SELECT *
            FROM config.DELIVERY_ZONE dz
            WHERE dz.CLIENT_ID = p_client_id
              AND dz.ACTIVE = TRUE
              AND UPPER(dz.COUNTRY) = v_country
              AND (
                    UPPER(COALESCE(dz.BASKET_TYPE,'ANY')) = 'ANY'
                    OR UPPER(dz.BASKET_TYPE) = v_basket_type
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
                    OR v_subtotal >= dz.MIN_ORDER_VALUE
                  )
              AND (
                    dz.MIN_DISTANCE_MILES IS NULL
                    OR (
                        v_distance_available
                        AND v_distance_miles >= dz.MIN_DISTANCE_MILES
                    )
                  )
              AND (
                    dz.MAX_DISTANCE_MILES IS NULL
                    OR (
                        v_distance_available
                        AND v_distance_miles < dz.MAX_DISTANCE_MILES
                    )
                  )
            ORDER BY dz.PRIORITY, dz.ZONE_ID
        LOOP
            v_matched_zone_count := v_matched_zone_count + 1;

            v_standard_method :=
                CASE
                    WHEN v_has_standard THEN
                        UPPER(
                            COALESCE(
                                NULLIF(
                                    TRIM(z.STANDARD_FULFILMENT_METHOD),
                                    ''
                                ),
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
                                NULLIF(
                                    TRIM(z.LIVESTOCK_FULFILMENT_METHOD),
                                    ''
                                ),
                                z.FULFILMENT_METHOD
                            )
                        )
                    ELSE NULL
                END;

            v_preference :=
                CASE
                    WHEN v_has_standard
                         AND v_has_livestock
                         AND v_standard_method IS DISTINCT FROM
                             v_livestock_method
                    THEN 'SPLIT_WHEN_REQUIRED'
                    ELSE 'CONSOLIDATE'
                END;

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
                        'carrierId',z.CARRIER_ID,
                        'price',z.DELIVERY_PRICE,
                        'currency',z.CURRENCY,
                        'requiresManualConfirmation',
                            z.REQUIRES_MANUAL_CONFIRMATION,
                        'distanceMiles',v_distance_miles,
                        'fulfilmentPlan',
                            jsonb_build_object(
                                'standardMethod',v_standard_method,
                                'livestockMethod',v_livestock_method
                            )
                    )
                );
        END LOOP;
    END IF;

    --------------------------------------------------------------------------
    -- Compatibility fallback until explicit delivery zones are configured.
    -- These remain manual-confirmation options and therefore cannot silently
    -- create paid delivery orders with an unknown price.
    --------------------------------------------------------------------------
    IF v_postcode_valid AND v_matched_zone_count = 0 THEN
        IF v_basket_type = 'STANDARD' THEN
            v_options :=
                v_options ||
                jsonb_build_array(
                    jsonb_build_object(
                        'code','STANDARD_CARRIER',
                        'label','Delivery',
                        'optionDescription',
                            'Delivery price requires confirmation.',
                        'fulfilmentMethod','CARRIER',
                        'fulfilmentPreference','CONSOLIDATE',
                        'basketType',v_basket_type,
                        'carrierId',NULL,
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
        ELSIF v_basket_type = 'LIVESTOCK' THEN
            v_options :=
                v_options ||
                jsonb_build_array(
                    jsonb_build_object(
                        'code','MEET_POINT',
                        'label','Meet halfway / arranged handover',
                        'optionDescription',
                            'The handover location and price require confirmation.',
                        'fulfilmentMethod','MEET_POINT',
                        'fulfilmentPreference','CONSOLIDATE',
                        'basketType',v_basket_type,
                        'carrierId',NULL,
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
                        'optionDescription',
                            'This mixed fish and product order requires a delivery arrangement.',
                        'fulfilmentMethod','LOCAL_DELIVERY',
                        'fulfilmentPreference','CONSOLIDATE',
                        'basketType',v_basket_type,
                        'carrierId',NULL,
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
                'postcode',
                    COALESCE(v_distance->>'postcode',v_postcode),
                'postcodeValid',v_postcode_valid,
                'distanceAvailable',v_distance_available,
                'distanceMiles',v_distance_miles,
                'distanceBasis',v_distance->>'distanceBasis',
                'statusCode',v_distance->>'code'
            ),
        'fulfilmentOptions',v_options
    );
END;
$$;