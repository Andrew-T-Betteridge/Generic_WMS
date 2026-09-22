\set ON_ERROR_STOP on

BEGIN;

-------------------------------------------------------------------------------
-- DYNETIC WMS 0.3.12
-- Generic checkout carrier rating and calculated-distance fulfilment.
-------------------------------------------------------------------------------

ALTER TABLE config.CARRIER_SERVICE
    ADD COLUMN IF NOT EXISTS MAX_LENGTH_PLUS_GIRTH_CM NUMERIC(10,3);

COMMENT ON COLUMN config.CARRIER_SERVICE.MAX_LENGTH_PLUS_GIRTH_CM IS
    'Maximum parcel length plus girth in centimetres: longest side + 2 x the two shorter sides.';

ALTER TABLE config.DELIVERY_ZONE
    ADD COLUMN IF NOT EXISTS PRICING_METHOD VARCHAR(30) NOT NULL DEFAULT 'FIXED',
    ADD COLUMN IF NOT EXISTS DISTANCE_RATE_PER_MILE NUMERIC(10,2),
    ADD COLUMN IF NOT EXISTS MINIMUM_DELIVERY_PRICE NUMERIC(10,2),
    ADD COLUMN IF NOT EXISTS SERVICE_LEVEL VARCHAR(50);

ALTER TABLE config.DELIVERY_ZONE
    DROP CONSTRAINT IF EXISTS ck_delivery_zone_pricing_method;

ALTER TABLE config.DELIVERY_ZONE
    ADD CONSTRAINT ck_delivery_zone_pricing_method
    CHECK (
        UPPER(PRICING_METHOD) IN (
            'FIXED',
            'DISTANCE',
            'CARRIER',
            'DISTANCE_PLUS_CARRIER'
        )
    );

COMMENT ON COLUMN config.DELIVERY_ZONE.PRICING_METHOD IS
    'FIXED, DISTANCE, CARRIER or DISTANCE_PLUS_CARRIER.';
COMMENT ON COLUMN config.DELIVERY_ZONE.DISTANCE_RATE_PER_MILE IS
    'Checkout charge per one-way postcode-centroid mile.';
COMMENT ON COLUMN config.DELIVERY_ZONE.MINIMUM_DELIVERY_PRICE IS
    'Minimum calculated local-delivery component.';
COMMENT ON COLUMN config.DELIVERY_ZONE.SERVICE_LEVEL IS
    'Optional carrier service used when pricing includes CARRIER.';

ALTER TABLE core.ORDER_HEADER
    ADD COLUMN IF NOT EXISTS FULFILMENT_OPTION_CODE VARCHAR(100);

COMMENT ON COLUMN core.ORDER_HEADER.FULFILMENT_OPTION_CODE IS
    'Checkout fulfilment option selected by the customer; distinct from carrier service level.';

COMMENT ON COLUMN core.SKU.EACH_WEIGHT IS
    'Physical/rating weight per sellable unit in kilograms.';
COMMENT ON COLUMN core.SKU.EACH_HEIGHT IS
    'Physical/rating height per sellable unit in centimetres.';
COMMENT ON COLUMN core.SKU.EACH_WIDTH IS
    'Physical/rating width per sellable unit in centimetres.';
COMMENT ON COLUMN core.SKU.EACH_DEPTH IS
    'Physical/rating depth/length per sellable unit in centimetres.';

CREATE OR REPLACE FUNCTION api.VALIDATE_BASKET(p_client_id VARCHAR,p_items JSONB)
RETURNS JSONB LANGUAGE plpgsql STABLE AS $$
DECLARE v_result JSONB;
BEGIN
 IF p_items IS NULL OR jsonb_typeof(p_items)<>'array' OR jsonb_array_length(p_items)=0 THEN
   RETURN jsonb_build_object(
     'valid',FALSE,
     'errors',jsonb_build_array(jsonb_build_object('code','EMPTY_BASKET','message','Basket is empty.')),
     'items','[]'::jsonb,
     'standardWeightKg',NULL,
     'standardShippingDataComplete',TRUE
   );
 END IF;

 WITH requested AS (
   SELECT x.sku_id,x.qty
   FROM jsonb_to_recordset(p_items) x(sku_id VARCHAR,qty NUMERIC)
 ),
 resolved AS (
   SELECT r.sku_id,r.qty,pv.PRODUCT_ID,p.PRODUCT_NAME,p.SLUG,p.DELIVERY_CLASS,p.CURRENCY,
          pv.VARIANT_NAME,pv.OPTION_VALUES,pv.WEB_PRICE,
          pv.SALE_TYPE,pv.AVAILABILITY_STATE,pv.EXPECTED_AVAILABLE_FROM,pv.EXPECTED_AVAILABLE_TO,
          pv.MIN_ORDER_QTY,pv.MAX_ORDER_QTY,pv.QTY_INCREMENT,
          s.EACH_WEIGHT,s.EACH_HEIGHT,s.EACH_WIDTH,s.EACH_DEPTH,
          COALESCE(a.AVAILABLE_QTY,0) AVAILABLE_QTY,
          CASE WHEN pv.SKU_ID IS NULL THEN 'SKU_NOT_FOR_SALE'
               WHEN pv.AVAILABILITY_STATE<>'AVAILABLE' THEN 'NOT_YET_AVAILABLE'
               WHEN r.qty IS NULL OR r.qty<=0 THEN 'INVALID_QTY'
               WHEN r.qty<pv.MIN_ORDER_QTY THEN 'BELOW_MIN_QTY'
               WHEN pv.MAX_ORDER_QTY IS NOT NULL AND r.qty>pv.MAX_ORDER_QTY THEN 'ABOVE_MAX_QTY'
               WHEN pv.QTY_INCREMENT>0 AND mod(r.qty-pv.MIN_ORDER_QTY,pv.QTY_INCREMENT)<>0 THEN 'INVALID_QTY_INCREMENT'
               WHEN COALESCE(a.AVAILABLE_QTY,0)<r.qty THEN 'INSUFFICIENT_STOCK'
               ELSE NULL END ERROR_CODE
   FROM requested r
   LEFT JOIN core.PRODUCT_VARIANT pv
     ON pv.CLIENT_ID=p_client_id AND pv.SKU_ID=r.sku_id AND pv.ACTIVE=TRUE
   LEFT JOIN core.PRODUCT p
     ON p.CLIENT_ID=pv.CLIENT_ID AND p.PRODUCT_ID=pv.PRODUCT_ID AND p.ACTIVE=TRUE
   LEFT JOIN core.SKU s
     ON s.CLIENT_ID=pv.CLIENT_ID AND s.SKU_ID=pv.SKU_ID
   LEFT JOIN api.CATALOG_VARIANT_AVAILABILITY a
     ON a.CLIENT_ID=pv.CLIENT_ID AND a.PRODUCT_ID=pv.PRODUCT_ID AND a.SKU_ID=pv.SKU_ID
 )
 SELECT jsonb_build_object(
   'valid',COUNT(*) FILTER(WHERE ERROR_CODE IS NOT NULL)=0,
   'currency',COALESCE(MAX(CURRENCY),'GBP'),
   'subtotal',COALESCE(SUM(CASE WHEN ERROR_CODE IS NULL THEN WEB_PRICE*qty ELSE 0 END),0),
   'hasStandard',COALESCE(BOOL_OR(UPPER(COALESCE(DELIVERY_CLASS,'STANDARD'))='STANDARD' AND ERROR_CODE IS NULL),FALSE),
   'hasLivestock',COALESCE(BOOL_OR(UPPER(COALESCE(DELIVERY_CLASS,''))='LIVESTOCK' AND ERROR_CODE IS NULL),FALSE),
   'deliveryClasses',COALESCE(jsonb_agg(DISTINCT DELIVERY_CLASS) FILTER(WHERE ERROR_CODE IS NULL),'[]'::jsonb),
   'standardWeightKg',
      CASE
        WHEN COUNT(*) FILTER(
               WHERE ERROR_CODE IS NULL
                 AND UPPER(COALESCE(DELIVERY_CLASS,'STANDARD'))='STANDARD'
             )=0 THEN 0
        WHEN BOOL_OR(
               EACH_WEIGHT IS NULL OR EACH_WEIGHT<=0
             ) FILTER(
               WHERE ERROR_CODE IS NULL
                 AND UPPER(COALESCE(DELIVERY_CLASS,'STANDARD'))='STANDARD'
             ) THEN NULL
        ELSE ROUND(
               COALESCE(
                 SUM(EACH_WEIGHT*qty) FILTER(
                   WHERE ERROR_CODE IS NULL
                     AND UPPER(COALESCE(DELIVERY_CLASS,'STANDARD'))='STANDARD'
                 ),0
               )::numeric,6
             )
      END,
   'standardShippingDataComplete',
      COALESCE(
        BOOL_AND(
          EACH_WEIGHT IS NOT NULL AND EACH_WEIGHT>0
          AND EACH_HEIGHT IS NOT NULL AND EACH_HEIGHT>0
          AND EACH_WIDTH IS NOT NULL AND EACH_WIDTH>0
          AND EACH_DEPTH IS NOT NULL AND EACH_DEPTH>0
        ) FILTER(
          WHERE ERROR_CODE IS NULL
            AND UPPER(COALESCE(DELIVERY_CLASS,'STANDARD'))='STANDARD'
        ),
        TRUE
      ),
   'items',
      COALESCE(
        jsonb_agg(
          jsonb_build_object(
            'skuId',sku_id,
            'qty',qty,
            'productId',PRODUCT_ID,
            'productName',PRODUCT_NAME,
            'slug',SLUG,
            'variantName',VARIANT_NAME,
            'options',OPTION_VALUES,
            'deliveryClass',DELIVERY_CLASS,
            'saleType',SALE_TYPE,
            'availabilityState',AVAILABILITY_STATE,
            'expectedAvailableFrom',EXPECTED_AVAILABLE_FROM,
            'expectedAvailableTo',EXPECTED_AVAILABLE_TO,
            'unitPrice',WEB_PRICE,
            'lineTotal',CASE WHEN WEB_PRICE IS NULL THEN NULL ELSE WEB_PRICE*qty END,
            'availableQty',AVAILABLE_QTY,
            'minOrderQty',MIN_ORDER_QTY,
            'maxOrderQty',MAX_ORDER_QTY,
            'qtyIncrement',QTY_INCREMENT,
            'unitWeightKg',EACH_WEIGHT,
            'unitHeightCm',EACH_HEIGHT,
            'unitWidthCm',EACH_WIDTH,
            'unitDepthCm',EACH_DEPTH,
            'lineWeightKg',CASE WHEN EACH_WEIGHT IS NULL THEN NULL ELSE ROUND((EACH_WEIGHT*qty)::numeric,6) END,
            'shippingDataComplete',
              EACH_WEIGHT IS NOT NULL AND EACH_WEIGHT>0
              AND EACH_HEIGHT IS NOT NULL AND EACH_HEIGHT>0
              AND EACH_WIDTH IS NOT NULL AND EACH_WIDTH>0
              AND EACH_DEPTH IS NOT NULL AND EACH_DEPTH>0,
            'valid',ERROR_CODE IS NULL,
            'errorCode',ERROR_CODE
          )
          ORDER BY sku_id
        ),
        '[]'::jsonb
      ),
   'errors',
      COALESCE(
        jsonb_agg(
          jsonb_build_object(
            'skuId',sku_id,
            'code',ERROR_CODE,
            'message',
              CASE ERROR_CODE
                WHEN 'SKU_NOT_FOR_SALE' THEN 'This item is not currently available for sale.'
                WHEN 'NOT_YET_AVAILABLE' THEN 'This item is not ready for normal checkout.'
                WHEN 'INVALID_QTY' THEN 'Quantity must be greater than zero.'
                WHEN 'BELOW_MIN_QTY' THEN 'Quantity is below the minimum for this offer.'
                WHEN 'ABOVE_MAX_QTY' THEN 'Quantity is above the maximum for this offer.'
                WHEN 'INVALID_QTY_INCREMENT' THEN 'Quantity does not match this offer''s required increment.'
                WHEN 'INSUFFICIENT_STOCK' THEN 'Requested quantity is not currently available.'
                ELSE 'Basket validation failed.'
              END
          )
        ) FILTER(WHERE ERROR_CODE IS NOT NULL),
        '[]'::jsonb
      )
 ) INTO v_result
 FROM resolved;

 RETURN v_result;
END;
$$;

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

CREATE OR REPLACE FUNCTION core.SELECT_CARRIER (
    p_client_id VARCHAR,
    p_container_id VARCHAR,
    p_delivery_class VARCHAR DEFAULT NULL,
    p_strategy VARCHAR DEFAULT 'CHEAPEST',
    p_user_id VARCHAR DEFAULT 'SYSTEM'
)
RETURNS TABLE (
    RESULT_STATUS VARCHAR,
    RESULT_CARRIER_ID VARCHAR,
    RESULT_SERVICE_LEVEL VARCHAR,
    RESULT_COST NUMERIC,
    RESULT_RULE_ID BIGINT,
    RESULT_MESSAGE TEXT
)
LANGUAGE plpgsql
AS $$
DECLARE
    v_container RECORD;
    v_order RECORD;
    v_weight NUMERIC(14,3);
    v_volume NUMERIC(18,3);
    v_height NUMERIC(14,3);
    v_width NUMERIC(14,3);
    v_depth NUMERIC(14,3);
    v_delivery_class VARCHAR(30);
    v_strategy VARCHAR(20);
    v_active_rule_count INTEGER;
    v_candidate RECORD;
    v_rule RECORD;
    v_rule_matched BOOLEAN;
    v_best_carrier VARCHAR(30);
    v_best_service VARCHAR(50);
    v_best_cost NUMERIC(12,2);
    v_best_rule BIGINT;
    v_best_priority INTEGER;
    v_cost NUMERIC(12,2);
    v_rate RECORD;
    v_candidate_priority INTEGER;
    v_candidate_rule BIGINT;
    v_user VARCHAR(20) := LEFT(COALESCE(NULLIF(p_user_id,''),'SYSTEM'),20);
BEGIN
    v_strategy := UPPER(COALESCE(NULLIF(p_strategy,''),'CHEAPEST'));

    IF v_strategy NOT IN ('CHEAPEST','PRIORITY') THEN
        RETURN QUERY SELECT 'ERROR'::VARCHAR,NULL::VARCHAR,NULL::VARCHAR,NULL::NUMERIC,NULL::BIGINT,
            'Unsupported strategy. Use CHEAPEST or PRIORITY.'::TEXT;
        RETURN;
    END IF;

    SELECT * INTO v_container
    FROM core.ORDER_CONTAINER
    WHERE CLIENT_ID=p_client_id AND CONTAINER_ID=p_container_id
    FOR UPDATE;

    IF NOT FOUND THEN
        RETURN QUERY SELECT 'ERROR'::VARCHAR,NULL::VARCHAR,NULL::VARCHAR,NULL::NUMERIC,NULL::BIGINT,
            'Container does not exist.'::TEXT;
        RETURN;
    END IF;

    SELECT * INTO v_order
    FROM core.ORDER_HEADER
    WHERE CLIENT_ID=p_client_id AND ORDER_ID=v_container.ORDER_ID;

    IF NOT FOUND THEN
        RETURN QUERY SELECT 'ERROR'::VARCHAR,NULL::VARCHAR,NULL::VARCHAR,NULL::NUMERIC,NULL::BIGINT,
            'Order does not exist.'::TEXT;
        RETURN;
    END IF;

    IF v_container.STATUS NOT IN ('PACKED','READY_TO_SHIP','OPEN') THEN
        RETURN QUERY SELECT 'ERROR'::VARCHAR,NULL::VARCHAR,NULL::VARCHAR,NULL::NUMERIC,NULL::BIGINT,
            format('Container status %s is not eligible for carrier selection.',v_container.STATUS)::TEXT;
        RETURN;
    END IF;

    -- Prefer actual container measurements. If weight/volume are not captured yet,
    -- derive practical estimates from packed SKU quantities.
    SELECT
        COALESCE(v_container.WEIGHT,
            SUM(COALESCE(s.EACH_WEIGHT,0) * COALESCE(sm.QTY_PICKED,0))),
        COALESCE(v_container.VOLUME,
            SUM(COALESCE(s.EACH_VOLUME,0) * COALESCE(sm.QTY_PICKED,0)))
    INTO v_weight, v_volume
    FROM core.SHIPPING_MANIFEST sm
    JOIN core.SKU s
      ON s.CLIENT_ID=sm.CLIENT_ID AND s.SKU_ID=sm.SKU_ID
    WHERE sm.CLIENT_ID=p_client_id
      AND sm.CONTAINER_ID=p_container_id;

    v_weight := COALESCE(v_weight,0);
    v_volume := COALESCE(v_volume,0);
    v_height := v_container.HEIGHT;
    v_width := v_container.WIDTH;
    v_depth := v_container.DEPTH;

    v_delivery_class := UPPER(COALESCE(
        NULLIF(p_delivery_class,''),
        NULLIF(v_container.DELIVERY_CLASS,''),
        'STANDARD'
    ));

    SELECT COUNT(*) INTO v_active_rule_count
    FROM config.CARRIER_SELECTION_RULE
    WHERE CLIENT_ID=p_client_id AND ACTIVE=TRUE;

    -- Clear the decision trail for a fresh run on this container.
    DELETE FROM audit.RULE_DECISION_LOG
    WHERE CLIENT_ID=p_client_id
      AND ENGINE_NAME='CARRIER_SELECTION'
      AND ENTITY_TYPE='ORDER_CONTAINER'
      AND ENTITY_ID=p_container_id;

    FOR v_candidate IN
        SELECT
            cs.CLIENT_ID,
            cs.CARRIER_ID,
            cs.SERVICE_LEVEL,
            cs.DESCRIPTION,
            cs.DISPATCH_METHOD,
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
          ON c.CLIENT_ID=cs.CLIENT_ID AND c.CARRIER_ID=cs.CARRIER_ID
        WHERE cs.CLIENT_ID=p_client_id
          AND cs.ACTIVE=TRUE
          AND c.ACTIVE=TRUE
        ORDER BY cs.SORT_SEQUENCE, cs.CARRIER_ID, cs.SERVICE_LEVEL
    LOOP
        -- Hard service constraints first.
        IF v_candidate.MAX_WEIGHT_KG IS NOT NULL AND v_weight > v_candidate.MAX_WEIGHT_KG THEN
            INSERT INTO audit.RULE_DECISION_LOG
                (CLIENT_ID,ENGINE_NAME,ENTITY_TYPE,ENTITY_ID,MATCHED,DECISION,REASON,DETAIL)
            VALUES
                (p_client_id,'CARRIER_SELECTION','ORDER_CONTAINER',p_container_id,FALSE,'REJECTED',
                 'Container exceeds service maximum weight.',
                 jsonb_build_object('carrier_id',v_candidate.CARRIER_ID,'service_level',v_candidate.SERVICE_LEVEL,
                                    'weight_kg',v_weight,'max_weight_kg',v_candidate.MAX_WEIGHT_KG));
            CONTINUE;
        END IF;

        IF v_candidate.MAX_VOLUME_CM3 IS NOT NULL AND v_volume > v_candidate.MAX_VOLUME_CM3 THEN
            CONTINUE;
        END IF;

        IF v_height IS NOT NULL AND v_candidate.MAX_HEIGHT_CM IS NOT NULL AND v_height > v_candidate.MAX_HEIGHT_CM THEN
            CONTINUE;
        END IF;
        IF v_width IS NOT NULL AND v_candidate.MAX_WIDTH_CM IS NOT NULL AND v_width > v_candidate.MAX_WIDTH_CM THEN
            CONTINUE;
        END IF;
        IF v_depth IS NOT NULL AND v_candidate.MAX_LENGTH_CM IS NOT NULL AND v_depth > v_candidate.MAX_LENGTH_CM THEN
            CONTINUE;
        END IF;

        IF v_delivery_class='LIVESTOCK' AND NOT v_candidate.LIVE_GOODS_ALLOWED THEN
            INSERT INTO audit.RULE_DECISION_LOG
                (CLIENT_ID,ENGINE_NAME,ENTITY_TYPE,ENTITY_ID,MATCHED,DECISION,REASON,DETAIL)
            VALUES
                (p_client_id,'CARRIER_SELECTION','ORDER_CONTAINER',p_container_id,FALSE,'REJECTED',
                 'Livestock requires a service explicitly approved for live goods.',
                 jsonb_build_object('carrier_id',v_candidate.CARRIER_ID,'service_level',v_candidate.SERVICE_LEVEL));
            CONTINUE;
        END IF;

        IF v_height IS NOT NULL
           AND v_width IS NOT NULL
           AND v_depth IS NOT NULL
           AND v_candidate.MAX_LENGTH_PLUS_GIRTH_CM IS NOT NULL
           AND (
                GREATEST(v_height,v_width,v_depth)
                + (
                    2 * (
                        (v_height + v_width + v_depth)
                        - GREATEST(v_height,v_width,v_depth)
                    )
                  )
               ) > v_candidate.MAX_LENGTH_PLUS_GIRTH_CM
        THEN
            CONTINUE;
        END IF;
        -- When rules exist for a client, a service must match at least one rule
        -- that targets it (or is intentionally generic).
        v_candidate_priority := 1000000;
        v_candidate_rule := NULL;
        v_rule_matched := FALSE;

        FOR v_rule IN
            SELECT *
            FROM config.CARRIER_SELECTION_RULE r
            WHERE r.CLIENT_ID=p_client_id
              AND r.ACTIVE=TRUE
              AND (r.CARRIER_ID IS NULL OR r.CARRIER_ID=v_candidate.CARRIER_ID)
              AND (r.SERVICE_LEVEL IS NULL OR r.SERVICE_LEVEL=v_candidate.SERVICE_LEVEL)
            ORDER BY r.PRIORITY,r.RULE_ID
        LOOP
            IF v_rule.MIN_WEIGHT_KG IS NOT NULL AND v_weight < v_rule.MIN_WEIGHT_KG THEN CONTINUE; END IF;
            IF v_rule.MAX_WEIGHT_KG IS NOT NULL AND v_weight > v_rule.MAX_WEIGHT_KG THEN CONTINUE; END IF;
            IF v_rule.MIN_VOLUME_CM3 IS NOT NULL AND v_volume < v_rule.MIN_VOLUME_CM3 THEN CONTINUE; END IF;
            IF v_rule.MAX_VOLUME_CM3 IS NOT NULL AND v_volume > v_rule.MAX_VOLUME_CM3 THEN CONTINUE; END IF;
            IF v_rule.MAX_ORDER_VALUE IS NOT NULL AND COALESCE(v_order.ORDER_VALUE,0) > v_rule.MAX_ORDER_VALUE THEN CONTINUE; END IF;
            IF v_rule.MIN_ORDER_VALUE IS NOT NULL AND COALESCE(v_order.ORDER_VALUE,0) < v_rule.MIN_ORDER_VALUE THEN CONTINUE; END IF;
            IF v_rule.DISPATCH_METHOD IS NOT NULL AND UPPER(COALESCE(v_order.DISPATCH_METHOD,'')) <> UPPER(v_rule.DISPATCH_METHOD) THEN CONTINUE; END IF;
            IF v_rule.DELIVERY_CLASS IS NOT NULL AND v_delivery_class <> UPPER(v_rule.DELIVERY_CLASS) THEN CONTINUE; END IF;
            IF v_rule.COUNTRY_CODE IS NOT NULL AND UPPER(LEFT(COALESCE(v_order.COUNTRY,''),3)) <> UPPER(v_rule.COUNTRY_CODE) THEN CONTINUE; END IF;

            IF NOT config.CARRIER_CONDITION_MATCH(
                v_rule.RULE_ID,
                v_weight,
                v_volume,
                v_order.ORDER_VALUE,
                v_delivery_class,
                v_order.DISPATCH_METHOD,
                v_order.SERVICE_LEVEL,
                v_order.COUNTRY,
                v_order.POSTCODE,
                v_order.FREE_DELIVERY
            ) THEN
                CONTINUE;
            END IF;

            v_rule_matched := TRUE;
            v_candidate_priority := LEAST(v_candidate_priority,v_rule.PRIORITY);
            IF v_candidate_rule IS NULL OR v_rule.PRIORITY=v_candidate_priority THEN
                v_candidate_rule := v_rule.RULE_ID;
            END IF;

            INSERT INTO audit.RULE_DECISION_LOG
                (CLIENT_ID,ENGINE_NAME,ENTITY_TYPE,ENTITY_ID,RULE_ID,RULE_NAME,MATCHED,DECISION,REASON,DETAIL)
            VALUES
                (p_client_id,'CARRIER_SELECTION','ORDER_CONTAINER',p_container_id,
                 v_rule.RULE_ID,v_rule.RULE_NAME,TRUE,'MATCHED','Carrier selection rule matched.',
                 jsonb_build_object('carrier_id',v_candidate.CARRIER_ID,'service_level',v_candidate.SERVICE_LEVEL,
                                    'priority',v_rule.PRIORITY));

            EXIT WHEN v_rule.STOP_ON_MATCH;
        END LOOP;

        IF v_active_rule_count>0 AND NOT v_rule_matched THEN
            CONTINUE;
        END IF;

        -- Best matching commercial rate band. Most specific postcode/country
        -- beats generic, then lower PRIORITY number.
        SELECT *
        INTO v_rate
        FROM config.CARRIER_SERVICE_RATE csr
        WHERE csr.CLIENT_ID=p_client_id
          AND csr.CARRIER_ID=v_candidate.CARRIER_ID
          AND csr.SERVICE_LEVEL=v_candidate.SERVICE_LEVEL
          AND csr.ACTIVE=TRUE
          AND v_weight >= csr.MIN_WEIGHT_KG
          AND (csr.MAX_WEIGHT_KG IS NULL OR v_weight <= csr.MAX_WEIGHT_KG)
          AND (csr.EFFECTIVE_FROM IS NULL OR csr.EFFECTIVE_FROM <= CURRENT_DATE)
          AND (csr.EFFECTIVE_TO IS NULL OR csr.EFFECTIVE_TO >= CURRENT_DATE)
          AND (csr.COUNTRY_CODE IS NULL OR UPPER(LEFT(COALESCE(v_order.COUNTRY,''),3))=UPPER(csr.COUNTRY_CODE))
          AND (csr.POSTCODE_PREFIX IS NULL OR UPPER(COALESCE(v_order.POSTCODE,'')) LIKE UPPER(csr.POSTCODE_PREFIX)||'%')
        ORDER BY
            CASE WHEN csr.POSTCODE_PREFIX IS NOT NULL THEN 0 ELSE 1 END,
            CASE WHEN csr.COUNTRY_CODE IS NOT NULL THEN 0 ELSE 1 END,
            csr.PRIORITY,
            CASE WHEN csr.MAX_WEIGHT_KG IS NOT NULL AND v_weight = csr.MAX_WEIGHT_KG THEN 0 ELSE 1 END,
            csr.MIN_WEIGHT_KG DESC,
            csr.RATE_ID
        LIMIT 1;

        IF FOUND THEN
            v_cost := ROUND((v_rate.BASE_COST + (v_rate.COST_PER_KG * v_weight) + v_rate.SURCHARGE)::NUMERIC,2);
        ELSE
            v_cost := ROUND((COALESCE(v_candidate.BASE_COST,0) + (COALESCE(v_candidate.COST_PER_KG,0) * v_weight))::NUMERIC,2);
        END IF;

        INSERT INTO audit.RULE_DECISION_LOG
            (CLIENT_ID,ENGINE_NAME,ENTITY_TYPE,ENTITY_ID,RULE_ID,MATCHED,DECISION,REASON,DETAIL)
        VALUES
            (p_client_id,'CARRIER_SELECTION','ORDER_CONTAINER',p_container_id,
             v_candidate_rule,TRUE,'ELIGIBLE','Carrier service is eligible.',
             jsonb_build_object('carrier_id',v_candidate.CARRIER_ID,'service_level',v_candidate.SERVICE_LEVEL,
                                'cost',v_cost,'weight_kg',v_weight,'delivery_class',v_delivery_class,
                                'priority',v_candidate_priority));

        IF v_best_carrier IS NULL
           OR (v_strategy='CHEAPEST' AND
               (v_cost < v_best_cost OR
                (v_cost=v_best_cost AND v_candidate_priority < v_best_priority) OR
                (v_cost=v_best_cost AND v_candidate_priority=v_best_priority AND
                 (v_candidate.CARRIER_ID,v_candidate.SERVICE_LEVEL) < (v_best_carrier,v_best_service))))
           OR (v_strategy='PRIORITY' AND
               (v_candidate_priority < v_best_priority OR
                (v_candidate_priority=v_best_priority AND v_cost < v_best_cost) OR
                (v_candidate_priority=v_best_priority AND v_cost=v_best_cost AND
                 (v_candidate.CARRIER_ID,v_candidate.SERVICE_LEVEL) < (v_best_carrier,v_best_service))))
        THEN
            v_best_carrier := v_candidate.CARRIER_ID;
            v_best_service := v_candidate.SERVICE_LEVEL;
            v_best_cost := v_cost;
            v_best_rule := v_candidate_rule;
            v_best_priority := v_candidate_priority;
        END IF;
    END LOOP;

    IF v_best_carrier IS NULL THEN
        UPDATE core.ORDER_CONTAINER
        SET CARRIER_ID=NULL,
            SERVICE_LEVEL=NULL,
            CARRIER_COST=NULL,
            CARRIER_SELECTION_SOURCE='NO_MATCH',
            CARRIER_SELECTION_RULE_ID=NULL,
            CARRIER_SELECTED_DSTAMP=now(),
            DELIVERY_CLASS=v_delivery_class
        WHERE CLIENT_ID=p_client_id AND CONTAINER_ID=p_container_id;

        RETURN QUERY SELECT 'NO_ELIGIBLE_SERVICE'::VARCHAR,NULL::VARCHAR,NULL::VARCHAR,NULL::NUMERIC,NULL::BIGINT,
            'No active carrier service satisfied the container constraints and selection rules.'::TEXT;
        RETURN;
    END IF;

    UPDATE core.ORDER_CONTAINER
    SET CARRIER_ID=v_best_carrier,
        SERVICE_LEVEL=v_best_service,
        CARRIER_COST=v_best_cost,
        CARRIER_SELECTION_SOURCE=v_strategy,
        CARRIER_SELECTION_RULE_ID=v_best_rule,
        CARRIER_SELECTED_DSTAMP=now(),
        CARRIER_OVERRIDE_REASON=NULL,
        DELIVERY_CLASS=v_delivery_class
    WHERE CLIENT_ID=p_client_id AND CONTAINER_ID=p_container_id;

    UPDATE core.SHIPPING_MANIFEST
    SET CARRIER_ID=v_best_carrier,
        SERVICE_LEVEL=v_best_service,
        DISPATCH_COST=v_best_cost,
        CARRIER_SELECTION_RULE_ID=v_best_rule
    WHERE CLIENT_ID=p_client_id AND CONTAINER_ID=p_container_id
      AND COALESCE(SHIPPED,'N')='N';

    INSERT INTO audit.RULE_DECISION_LOG
        (CLIENT_ID,ENGINE_NAME,ENTITY_TYPE,ENTITY_ID,RULE_ID,MATCHED,DECISION,REASON,DETAIL)
    VALUES
        (p_client_id,'CARRIER_SELECTION','ORDER_CONTAINER',p_container_id,
         v_best_rule,TRUE,'SELECTED','Carrier service selected.',
         jsonb_build_object('carrier_id',v_best_carrier,'service_level',v_best_service,
                            'cost',v_best_cost,'strategy',v_strategy,'selected_by',v_user));

    RETURN QUERY SELECT 'SELECTED'::VARCHAR,v_best_carrier::VARCHAR,v_best_service::VARCHAR,
        v_best_cost::NUMERIC,v_best_rule,
        format('Selected %s / %s at estimated cost %s using %s strategy.',
               v_best_carrier,v_best_service,v_best_cost,v_strategy)::TEXT;
END;
$$;

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

-------------------------------------------------------------------------------
-- FINatics authoritative fulfilment configuration.
-------------------------------------------------------------------------------

UPDATE config.SYSTEM_SETTING
   SET VALUE_TEXT='CV13 6AG',
       DESCRIPTION='Origin postcode used for FINatics postcode-centroid delivery distance calculations',
       ACTIVE=TRUE,
       LAST_UPDATED_DSTAMP=now()
 WHERE CLIENT_ID='FINATICS'
   AND SITE_ID IS NULL
   AND SETTING_KEY='DELIVERY_ORIGIN_POSTCODE';

INSERT INTO config.SYSTEM_SETTING (
    CLIENT_ID,
    SITE_ID,
    SETTING_KEY,
    VALUE_TEXT,
    DESCRIPTION,
    ACTIVE
)
SELECT
    'FINATICS',
    NULL,
    'DELIVERY_ORIGIN_POSTCODE',
    'CV13 6AG',
    'Origin postcode used for FINatics postcode-centroid delivery distance calculations',
    TRUE
WHERE NOT EXISTS (
    SELECT 1
      FROM config.SYSTEM_SETTING
     WHERE CLIENT_ID='FINATICS'
       AND SITE_ID IS NULL
       AND SETTING_KEY='DELIVERY_ORIGIN_POSTCODE'
);

INSERT INTO config.DELIVERY_CLASS_CONTROL (
    CLIENT_ID,
    DELIVERY_CLASS,
    CARRIER_DESPATCH_ENABLED,
    HOLD_REASON
)
VALUES (
    'FINATICS',
    'LIVESTOCK',
    FALSE,
    'LIVESTOCK MUST NOT USE STANDARD CARRIER DESPATCH'
)
ON CONFLICT (CLIENT_ID,DELIVERY_CLASS)
DO UPDATE SET
    CARRIER_DESPATCH_ENABLED=FALSE,
    HOLD_REASON='LIVESTOCK MUST NOT USE STANDARD CARRIER DESPATCH',
    LAST_UPDATE_DSTAMP=now();

-------------------------------------------------------------------------------
-- Evri public Standard drop-off rates verified 2026-09-22.
-- These are configuration, not hard-coded application logic.
-------------------------------------------------------------------------------

INSERT INTO config.CARRIER (
    CLIENT_ID,
    CARRIER_ID,
    DESCRIPTION,
    ACTIVE,
    API_ENABLED
)
VALUES (
    'FINATICS',
    'EVRI',
    'Evri',
    TRUE,
    FALSE
)
ON CONFLICT (CLIENT_ID,CARRIER_ID)
DO UPDATE SET
    DESCRIPTION=EXCLUDED.DESCRIPTION,
    ACTIVE=TRUE,
    API_ENABLED=FALSE,
    LAST_UPDATED_DSTAMP=now();

INSERT INTO config.CARRIER_SERVICE (
    CLIENT_ID,
    CARRIER_ID,
    SERVICE_LEVEL,
    DESCRIPTION,
    DISPATCH_METHOD,
    ACTIVE,
    MAX_WEIGHT_KG,
    MAX_LENGTH_CM,
    MAX_LENGTH_PLUS_GIRTH_CM,
    MAX_PARCELS,
    BASE_COST,
    COST_PER_KG,
    REQUIRES_MANUAL_APPROVAL,
    LIVE_GOODS_ALLOWED,
    SORT_SEQUENCE
)
VALUES (
    'FINATICS',
    'EVRI',
    'STANDARD_DROPOFF',
    'Evri Standard drop-off to home/work address',
    'CARRIER',
    TRUE,
    15,
    120,
    245,
    1,
    NULL,
    0,
    FALSE,
    FALSE,
    10
)
ON CONFLICT (CLIENT_ID,CARRIER_ID,SERVICE_LEVEL)
DO UPDATE SET
    DESCRIPTION=EXCLUDED.DESCRIPTION,
    DISPATCH_METHOD=EXCLUDED.DISPATCH_METHOD,
    ACTIVE=TRUE,
    MAX_WEIGHT_KG=EXCLUDED.MAX_WEIGHT_KG,
    MAX_LENGTH_CM=EXCLUDED.MAX_LENGTH_CM,
    MAX_LENGTH_PLUS_GIRTH_CM=EXCLUDED.MAX_LENGTH_PLUS_GIRTH_CM,
    MAX_PARCELS=EXCLUDED.MAX_PARCELS,
    BASE_COST=EXCLUDED.BASE_COST,
    COST_PER_KG=EXCLUDED.COST_PER_KG,
    REQUIRES_MANUAL_APPROVAL=EXCLUDED.REQUIRES_MANUAL_APPROVAL,
    LIVE_GOODS_ALLOWED=FALSE,
    SORT_SEQUENCE=EXCLUDED.SORT_SEQUENCE,
    LAST_UPDATED_DSTAMP=now();

DELETE FROM config.CARRIER_SERVICE_RATE
 WHERE CLIENT_ID='FINATICS'
   AND CARRIER_ID='EVRI'
   AND SERVICE_LEVEL='STANDARD_DROPOFF';

INSERT INTO config.CARRIER_SERVICE_RATE (
    CLIENT_ID,
    CARRIER_ID,
    SERVICE_LEVEL,
    MIN_WEIGHT_KG,
    MAX_WEIGHT_KG,
    COUNTRY_CODE,
    BASE_COST,
    COST_PER_KG,
    SURCHARGE,
    ACTIVE,
    PRIORITY,
    EFFECTIVE_FROM
)
VALUES
    ('FINATICS','EVRI','STANDARD_DROPOFF',0.000001,1.000000,'GB',3.29,0,0,TRUE,100,DATE '2026-09-22'),
    ('FINATICS','EVRI','STANDARD_DROPOFF',1.000001,2.000000,'GB',4.79,0,0,TRUE,100,DATE '2026-09-22'),
    ('FINATICS','EVRI','STANDARD_DROPOFF',2.000001,5.000000,'GB',6.59,0,0,TRUE,100,DATE '2026-09-22'),
    ('FINATICS','EVRI','STANDARD_DROPOFF',5.000001,10.000000,'GB',6.68,0,0,TRUE,100,DATE '2026-09-22'),
    ('FINATICS','EVRI','STANDARD_DROPOFF',10.000001,15.000000,'GB',10.28,0,0,TRUE,100,DATE '2026-09-22');

DELETE FROM config.CARRIER_SELECTION_RULE
 WHERE CLIENT_ID='FINATICS'
   AND RULE_NAME='FINATICS EVRI STANDARD GOODS';

INSERT INTO config.CARRIER_SELECTION_RULE (
    CLIENT_ID,
    RULE_NAME,
    PRIORITY,
    ACTIVE,
    CARRIER_ID,
    SERVICE_LEVEL,
    MIN_WEIGHT_KG,
    MAX_WEIGHT_KG,
    DISPATCH_METHOD,
    DELIVERY_CLASS,
    COUNTRY_CODE,
    STOP_ON_MATCH
)
VALUES (
    'FINATICS',
    'FINATICS EVRI STANDARD GOODS',
    10,
    TRUE,
    'EVRI',
    'STANDARD_DROPOFF',
    0.000001,
    15,
    'CARRIER',
    'STANDARD',
    'GB',
    TRUE
);

-------------------------------------------------------------------------------
-- FINatics checkout delivery zones.
--
-- 0-50 miles:
--   personal delivery = GBP 1.00 per one-way postcode-centroid mile, minimum GBP 5.00.
--
-- 50-100 miles:
--   meet halfway = GBP 0.50 per one-way postcode-centroid mile.
--
-- Over 100 miles:
--   no automatic paid livestock option; existing manual fallback remains.
-------------------------------------------------------------------------------

DELETE FROM config.DELIVERY_ZONE
 WHERE CLIENT_ID='FINATICS'
   AND ZONE_ID IN (
       'LOCAL-CV13',

       'STANDARD_EVRI_GB',
       'LIVESTOCK_LOCAL_0_50',
       'LIVESTOCK_MEET_50_100',
       'MIXED_TOGETHER_0_50',
       'MIXED_SPLIT_0_50',
       'MIXED_TOGETHER_MEET_50_100',
       'MIXED_SPLIT_MEET_50_100'
   );

INSERT INTO config.DELIVERY_ZONE (
    CLIENT_ID,
    ZONE_ID,
    ZONE_NAME,
    FULFILMENT_METHOD,
    COUNTRY,
    MIN_DISTANCE_MILES,
    MAX_DISTANCE_MILES,
    DELIVERY_PRICE,
    CURRENCY,
    REQUIRES_MANUAL_CONFIRMATION,
    PRIORITY,
    ACTIVE,
    BASKET_TYPE,
    STANDARD_FULFILMENT_METHOD,
    LIVESTOCK_FULFILMENT_METHOD,
    CARRIER_ID,
    SERVICE_LEVEL,
    PRICING_METHOD,
    DISTANCE_RATE_PER_MILE,
    MINIMUM_DELIVERY_PRICE,
    OPTION_DESCRIPTION
)
VALUES
(
    'FINATICS',
    'STANDARD_EVRI_GB',
    'Evri Standard Delivery',
    'CARRIER',
    'GB',
    NULL,
    NULL,
    NULL,
    'GBP',
    FALSE,
    10,
    TRUE,
    'STANDARD',
    'CARRIER',
    NULL,
    'EVRI',
    'STANDARD_DROPOFF',
    'CARRIER',
    NULL,
    NULL,
    'Tracked Evri Standard delivery. Price is calculated from the order weight.'
),
(
    'FINATICS',
    'LIVESTOCK_LOCAL_0_50',
    'FINatics Personal Delivery',
    'LOCAL_DELIVERY',
    'GB',
    0,
    50,
    NULL,
    'GBP',
    FALSE,
    20,
    TRUE,
    'LIVESTOCK',
    NULL,
    'LOCAL_DELIVERY',
    NULL,
    NULL,
    'DISTANCE',
    1.00,
    5.00,
    'FINatics personally delivers your fish to your delivery address.'
),
(
    'FINATICS',
    'LIVESTOCK_MEET_50_100',
    'Meet Halfway',
    'MEET_POINT',
    'GB',
    50,
    100,
    NULL,
    'GBP',
    FALSE,
    30,
    TRUE,
    'LIVESTOCK',
    NULL,
    'MEET_POINT',
    NULL,
    NULL,
    'DISTANCE',
    0.50,
    NULL,
    'Meet FINatics approximately halfway for a personal fish handover.'
),
(
    'FINATICS',
    'MIXED_TOGETHER_0_50',
    'Deliver Everything Together',
    'LOCAL_DELIVERY',
    'GB',
    0,
    50,
    NULL,
    'GBP',
    FALSE,
    20,
    TRUE,
    'MIXED',
    'LOCAL_DELIVERY',
    'LOCAL_DELIVERY',
    NULL,
    NULL,
    'DISTANCE',
    1.00,
    5.00,
    'Fish and dry goods are delivered together personally by FINatics.'
),
(
    'FINATICS',
    'MIXED_SPLIT_0_50',
    'Split Delivery',
    'LOCAL_DELIVERY',
    'GB',
    0,
    50,
    NULL,
    'GBP',
    FALSE,
    21,
    TRUE,
    'MIXED',
    'CARRIER',
    'LOCAL_DELIVERY',
    'EVRI',
    'STANDARD_DROPOFF',
    'DISTANCE_PLUS_CARRIER',
    1.00,
    5.00,
    'Fish are delivered personally by FINatics and dry goods are sent separately by Evri.'
),
(
    'FINATICS',
    'MIXED_TOGETHER_MEET_50_100',
    'Meet Halfway - Whole Order',
    'MEET_POINT',
    'GB',
    50,
    100,
    NULL,
    'GBP',
    FALSE,
    30,
    TRUE,
    'MIXED',
    'MEET_POINT',
    'MEET_POINT',
    NULL,
    NULL,
    'DISTANCE',
    0.50,
    NULL,
    'Meet FINatics approximately halfway and receive the whole order together.'
),
(
    'FINATICS',
    'MIXED_SPLIT_MEET_50_100',
    'Meet Halfway + Evri',
    'MEET_POINT',
    'GB',
    50,
    100,
    NULL,
    'GBP',
    FALSE,
    31,
    TRUE,
    'MIXED',
    'CARRIER',
    'MEET_POINT',
    'EVRI',
    'STANDARD_DROPOFF',
    'DISTANCE_PLUS_CARRIER',
    0.50,
    NULL,
    'Meet FINatics approximately halfway for the fish while dry goods are sent separately by Evri.'
);
-------------------------------------------------------------------------------
-- Rounded postcode distances are stored to 2dp.
-- Keep exactly 50.00 miles in local delivery and exactly 100.00 in meet-halfway.
-------------------------------------------------------------------------------

UPDATE config.DELIVERY_ZONE
SET MAX_DISTANCE_MILES=50.01
WHERE CLIENT_ID='FINATICS'
  AND ZONE_ID IN (
      'LIVESTOCK_LOCAL_0_50',
      'MIXED_TOGETHER_0_50',
      'MIXED_SPLIT_0_50'
  );

UPDATE config.DELIVERY_ZONE
SET MIN_DISTANCE_MILES=50.01,
    MAX_DISTANCE_MILES=100.01
WHERE CLIENT_ID='FINATICS'
  AND ZONE_ID IN (
      'LIVESTOCK_MEET_50_100',
      'MIXED_TOGETHER_MEET_50_100',
      'MIXED_SPLIT_MEET_50_100'
  );

-------------------------------------------------------------------------------
-- RELEASE VERSION
-------------------------------------------------------------------------------

UPDATE config.SYSTEM_VERSION
SET IS_CURRENT=FALSE
WHERE PRODUCT_CODE='DYNETIC_WMS'
  AND IS_CURRENT=TRUE
  AND VERSION_NUMBER <> '0.3.12';

INSERT INTO config.SYSTEM_VERSION (
    PRODUCT_CODE,
    PRODUCT_NAME,
    VERSION_NUMBER,
    VERSION_MAJOR,
    VERSION_MINOR,
    VERSION_PATCH,
    BUILD_NUMBER,
    RELEASE_CHANNEL,
    RELEASE_DATE,
    DESCRIPTION,
    IS_CURRENT
)
VALUES (
    'DYNETIC_WMS',
    'DYNETIC WMS',
    '0.3.12',
    0,
    3,
    12,
    0,
    'RELEASE',
    CURRENT_DATE,
    'Add calculated local delivery, carrier quoting, mixed-basket shipping and FINatics Evri configuration.',
    TRUE
)
ON CONFLICT (PRODUCT_CODE, VERSION_NUMBER)
DO UPDATE SET
    PRODUCT_NAME=EXCLUDED.PRODUCT_NAME,
    VERSION_MAJOR=EXCLUDED.VERSION_MAJOR,
    VERSION_MINOR=EXCLUDED.VERSION_MINOR,
    VERSION_PATCH=EXCLUDED.VERSION_PATCH,
    BUILD_NUMBER=EXCLUDED.BUILD_NUMBER,
    RELEASE_CHANNEL=EXCLUDED.RELEASE_CHANNEL,
    RELEASE_DATE=EXCLUDED.RELEASE_DATE,
    DESCRIPTION=EXCLUDED.DESCRIPTION,
    IS_CURRENT=TRUE;

COMMIT;
