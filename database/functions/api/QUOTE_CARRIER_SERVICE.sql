CREATE OR REPLACE FUNCTION api.QUOTE_CARRIER_SERVICE(
    p_client_id VARCHAR,
    p_basket JSONB,
    p_country VARCHAR DEFAULT 'GB',
    p_postcode TEXT DEFAULT NULL,
    p_carrier_id VARCHAR DEFAULT NULL,
    p_service_level VARCHAR DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
STABLE
AS $$
DECLARE
    v_country TEXT := UPPER(COALESCE(NULLIF(TRIM(p_country),''),'GB'));
    v_postcode TEXT := regexp_replace(UPPER(COALESCE(p_postcode,'')),'[[:space:]]','','g');
    v_standard_count INTEGER := 0;
    v_standard_units NUMERIC := 0;
    v_weight_kg NUMERIC;
    v_shipping_data_complete BOOLEAN := TRUE;
    v_item_length_cm NUMERIC;
    v_item_width_cm NUMERIC;
    v_item_height_cm NUMERIC;
    v_candidate RECORD;
    v_rate RECORD;
    v_cost NUMERIC;
    v_best_cost NUMERIC;
    v_best_carrier VARCHAR;
    v_best_service VARCHAR;
    v_best_rate_id BIGINT;
    v_best_manual BOOLEAN := TRUE;
    v_rejection_count INTEGER := 0;
    v_has_rate BOOLEAN := FALSE;
BEGIN
    IF p_basket IS NULL
       OR jsonb_typeof(p_basket)<>'object'
       OR NOT COALESCE((p_basket->>'valid')::boolean,FALSE)
    THEN
        RETURN jsonb_build_object(
            'quoted',FALSE,
            'code','INVALID_BASKET',
            'message','A valid server-side basket is required for carrier rating.',
            'requiresManualConfirmation',TRUE
        );
    END IF;

    WITH standard_items AS (
        SELECT
            i.item,
            NULLIF(i.item->>'qty','')::numeric AS qty,
            NULLIF(i.item->>'unitWeightKg','')::numeric AS unit_weight_kg,
            NULLIF(i.item->>'unitHeightCm','')::numeric AS unit_height_cm,
            NULLIF(i.item->>'unitWidthCm','')::numeric AS unit_width_cm,
            NULLIF(i.item->>'unitDepthCm','')::numeric AS unit_depth_cm
        FROM jsonb_array_elements(COALESCE(p_basket->'items','[]'::jsonb)) i(item)
        WHERE COALESCE((i.item->>'valid')::boolean,FALSE)
          AND UPPER(COALESCE(i.item->>'deliveryClass','STANDARD'))='STANDARD'
    ),
    shaped AS (
        SELECT *,
               GREATEST(unit_height_cm,unit_width_cm,unit_depth_cm) AS item_length_cm,
               (
                   unit_height_cm + unit_width_cm + unit_depth_cm
                   - GREATEST(unit_height_cm,unit_width_cm,unit_depth_cm)
                   - LEAST(unit_height_cm,unit_width_cm,unit_depth_cm)
               ) AS item_width_cm,
               LEAST(unit_height_cm,unit_width_cm,unit_depth_cm) AS item_height_cm
        FROM standard_items
    )
    SELECT
        COUNT(*)::integer,
        COALESCE(SUM(qty),0),
        CASE
            WHEN BOOL_OR(unit_weight_kg IS NULL OR unit_weight_kg<=0) THEN NULL
            ELSE ROUND(COALESCE(SUM(unit_weight_kg*qty),0)::numeric,6)
        END,
        COALESCE(
            BOOL_AND(
                unit_weight_kg IS NOT NULL AND unit_weight_kg>0
                AND unit_height_cm IS NOT NULL AND unit_height_cm>0
                AND unit_width_cm IS NOT NULL AND unit_width_cm>0
                AND unit_depth_cm IS NOT NULL AND unit_depth_cm>0
            ),
            TRUE
        ),
        MAX(item_length_cm),
        MAX(item_width_cm),
        MAX(item_height_cm)
    INTO
        v_standard_count,
        v_standard_units,
        v_weight_kg,
        v_shipping_data_complete,
        v_item_length_cm,
        v_item_width_cm,
        v_item_height_cm
    FROM shaped;

    IF v_standard_count=0 THEN
        RETURN jsonb_build_object(
            'quoted',FALSE,
            'code','NO_STANDARD_ITEMS',
            'message','There are no standard carrier-eligible items in this basket.',
            'requiresManualConfirmation',TRUE
        );
    END IF;

    IF v_weight_kg IS NULL OR v_weight_kg<=0 THEN
        RETURN jsonb_build_object(
            'quoted',FALSE,
            'code','CARRIER_WEIGHT_MISSING',
            'message','Carrier delivery cannot be priced until every standard SKU has a positive weight in kilograms.',
            'shippingWeightKg',v_weight_kg,
            'shippingDataComplete',FALSE,
            'requiresManualConfirmation',TRUE
        );
    END IF;

    FOR v_candidate IN
        SELECT
            cs.CLIENT_ID,
            cs.CARRIER_ID,
            cs.SERVICE_LEVEL,
            cs.DESCRIPTION,
            cs.MAX_WEIGHT_KG,
            cs.MAX_LENGTH_CM,
            cs.MAX_WIDTH_CM,
            cs.MAX_HEIGHT_CM,
            cs.MAX_LENGTH_PLUS_GIRTH_CM,
            cs.MAX_VOLUME_CM3,
            cs.BASE_COST,
            cs.COST_PER_KG,
            cs.REQUIRES_MANUAL_APPROVAL,
            cs.LIVE_GOODS_ALLOWED,
            cs.SORT_SEQUENCE
        FROM config.CARRIER_SERVICE cs
        JOIN config.CARRIER c
          ON c.CLIENT_ID=cs.CLIENT_ID
         AND c.CARRIER_ID=cs.CARRIER_ID
        WHERE cs.CLIENT_ID=p_client_id
          AND cs.ACTIVE=TRUE
          AND c.ACTIVE=TRUE
          AND (p_carrier_id IS NULL OR cs.CARRIER_ID=p_carrier_id)
          AND (p_service_level IS NULL OR cs.SERVICE_LEVEL=p_service_level)
          AND COALESCE(cs.LIVE_GOODS_ALLOWED,FALSE)=FALSE
        ORDER BY cs.SORT_SEQUENCE,cs.CARRIER_ID,cs.SERVICE_LEVEL
    LOOP
        IF v_candidate.MAX_WEIGHT_KG IS NOT NULL
           AND v_weight_kg>v_candidate.MAX_WEIGHT_KG
        THEN
            v_rejection_count := v_rejection_count + 1;
            CONTINUE;
        END IF;

        IF v_shipping_data_complete THEN
            IF v_candidate.MAX_LENGTH_CM IS NOT NULL
               AND v_item_length_cm>v_candidate.MAX_LENGTH_CM
            THEN
                v_rejection_count := v_rejection_count + 1;
                CONTINUE;
            END IF;

            IF v_candidate.MAX_WIDTH_CM IS NOT NULL
               AND v_item_width_cm>v_candidate.MAX_WIDTH_CM
            THEN
                v_rejection_count := v_rejection_count + 1;
                CONTINUE;
            END IF;

            IF v_candidate.MAX_HEIGHT_CM IS NOT NULL
               AND v_item_height_cm>v_candidate.MAX_HEIGHT_CM
            THEN
                v_rejection_count := v_rejection_count + 1;
                CONTINUE;
            END IF;

            IF v_candidate.MAX_LENGTH_PLUS_GIRTH_CM IS NOT NULL
               AND (
                    v_item_length_cm
                    + (2 * (v_item_width_cm + v_item_height_cm))
                   ) > v_candidate.MAX_LENGTH_PLUS_GIRTH_CM
            THEN
                v_rejection_count := v_rejection_count + 1;
                CONTINUE;
            END IF;
        END IF;

        SELECT csr.*
        INTO v_rate
        FROM config.CARRIER_SERVICE_RATE csr
        WHERE csr.CLIENT_ID=p_client_id
          AND csr.CARRIER_ID=v_candidate.CARRIER_ID
          AND csr.SERVICE_LEVEL=v_candidate.SERVICE_LEVEL
          AND csr.ACTIVE=TRUE
          AND v_weight_kg>=csr.MIN_WEIGHT_KG
          AND (csr.MAX_WEIGHT_KG IS NULL OR v_weight_kg<=csr.MAX_WEIGHT_KG)
          AND (csr.EFFECTIVE_FROM IS NULL OR csr.EFFECTIVE_FROM<=CURRENT_DATE)
          AND (csr.EFFECTIVE_TO IS NULL OR csr.EFFECTIVE_TO>=CURRENT_DATE)
          AND (
                csr.COUNTRY_CODE IS NULL
                OR UPPER(csr.COUNTRY_CODE)=v_country
              )
          AND (
                csr.POSTCODE_PREFIX IS NULL
                OR v_postcode LIKE
                   regexp_replace(
                       UPPER(csr.POSTCODE_PREFIX),
                       '[[:space:]]',
                       '',
                       'g'
                   ) || '%'
              )
        ORDER BY
            CASE WHEN csr.POSTCODE_PREFIX IS NOT NULL THEN 0 ELSE 1 END,
            CASE WHEN csr.COUNTRY_CODE IS NOT NULL THEN 0 ELSE 1 END,
            csr.PRIORITY,
            CASE WHEN csr.MAX_WEIGHT_KG IS NOT NULL AND v_weight_kg = csr.MAX_WEIGHT_KG THEN 0 ELSE 1 END,
            csr.MIN_WEIGHT_KG DESC,
            csr.RATE_ID
        LIMIT 1;

        v_has_rate := FOUND;

        IF v_has_rate THEN
            v_cost :=
                ROUND(
                    (
                        COALESCE(v_rate.BASE_COST,0)
                        + COALESCE(v_rate.COST_PER_KG,0)*v_weight_kg
                        + COALESCE(v_rate.SURCHARGE,0)
                    )::numeric,
                    2
                );
        ELSIF v_candidate.BASE_COST IS NOT NULL THEN
            v_cost :=
                ROUND(
                    (
                        v_candidate.BASE_COST
                        + COALESCE(v_candidate.COST_PER_KG,0)*v_weight_kg
                    )::numeric,
                    2
                );
        ELSE
            CONTINUE;
        END IF;

        IF v_best_carrier IS NULL
           OR v_cost<v_best_cost
           OR (
                v_cost=v_best_cost
                AND (
                    v_candidate.CARRIER_ID,
                    v_candidate.SERVICE_LEVEL
                ) < (
                    v_best_carrier,
                    v_best_service
                )
              )
        THEN
            v_best_carrier := v_candidate.CARRIER_ID;
            v_best_service := v_candidate.SERVICE_LEVEL;
            v_best_cost := v_cost;
            v_best_rate_id := CASE WHEN v_has_rate THEN v_rate.RATE_ID ELSE NULL END;
            v_best_manual :=
                COALESCE(v_candidate.REQUIRES_MANUAL_APPROVAL,FALSE)
                OR NOT v_shipping_data_complete;
        END IF;
    END LOOP;

    IF v_best_carrier IS NULL THEN
        RETURN jsonb_build_object(
            'quoted',FALSE,
            'code','NO_ELIGIBLE_CARRIER_SERVICE',
            'message','No active carrier service can safely accept this standard-goods basket.',
            'shippingWeightKg',v_weight_kg,
            'shippingDataComplete',v_shipping_data_complete,
            'maxItemLengthCm',v_item_length_cm,
            'maxItemWidthCm',v_item_width_cm,
            'maxItemHeightCm',v_item_height_cm,
            'lengthPlusGirthCm',
                CASE WHEN v_shipping_data_complete THEN
                    v_item_length_cm + (2 * (v_item_width_cm + v_item_height_cm))
                ELSE NULL END,
            'rejectedServiceCount',v_rejection_count,
            'requiresManualConfirmation',TRUE
        );
    END IF;

    RETURN jsonb_build_object(
        'quoted',TRUE,
        'code',
            CASE
                WHEN v_shipping_data_complete THEN 'QUOTED'
                ELSE 'QUOTED_DIMENSIONS_INCOMPLETE'
            END,
        'carrierId',v_best_carrier,
        'serviceLevel',v_best_service,
        'price',v_best_cost,
        'currency',COALESCE(p_basket->>'currency','GBP'),
        'rateId',v_best_rate_id,
        'shippingWeightKg',v_weight_kg,
        'standardItemUnits',v_standard_units,
        'shippingDataComplete',v_shipping_data_complete,
        'maxItemLengthCm',v_item_length_cm,
        'maxItemWidthCm',v_item_width_cm,
        'maxItemHeightCm',v_item_height_cm,
            'lengthPlusGirthCm',
                CASE WHEN v_shipping_data_complete THEN
                    v_item_length_cm + (2 * (v_item_width_cm + v_item_height_cm))
                ELSE NULL END,
        'dimensionBasis','MAX_ITEM_DIMENSIONS_NOT_CARTONISED',
        'requiresManualConfirmation',v_best_manual
    );
END;
$$;