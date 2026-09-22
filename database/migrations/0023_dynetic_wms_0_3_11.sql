\set ON_ERROR_STOP on

BEGIN;

ALTER TABLE config.DELIVERY_ZONE
    ADD COLUMN IF NOT EXISTS BASKET_TYPE VARCHAR(20) NOT NULL DEFAULT 'ANY',
    ADD COLUMN IF NOT EXISTS STANDARD_FULFILMENT_METHOD VARCHAR(30),
    ADD COLUMN IF NOT EXISTS LIVESTOCK_FULFILMENT_METHOD VARCHAR(30),
    ADD COLUMN IF NOT EXISTS CARRIER_ID VARCHAR(30),
    ADD COLUMN IF NOT EXISTS OPTION_DESCRIPTION VARCHAR(250);

COMMENT ON COLUMN config.DELIVERY_ZONE.BASKET_TYPE IS
'Basket classification for this delivery option: ANY, STANDARD, LIVESTOCK or MIXED.';

COMMENT ON COLUMN config.DELIVERY_ZONE.STANDARD_FULFILMENT_METHOD IS
'Fulfilment method used for STANDARD lines when this option is selected.';

COMMENT ON COLUMN config.DELIVERY_ZONE.LIVESTOCK_FULFILMENT_METHOD IS
'Fulfilment method used for LIVESTOCK lines when this option is selected.';

COMMENT ON COLUMN config.DELIVERY_ZONE.CARRIER_ID IS
'Optional carrier identifier for carrier-backed fulfilment, for example EVRI.';

COMMENT ON COLUMN config.DELIVERY_ZONE.OPTION_DESCRIPTION IS
'Customer-facing explanatory text returned by the delivery options API.';

ALTER TABLE config.DELIVERY_ZONE
    DROP CONSTRAINT IF EXISTS CK_DELIVERY_ZONE_BASKET_TYPE;

ALTER TABLE config.DELIVERY_ZONE
    ADD CONSTRAINT CK_DELIVERY_ZONE_BASKET_TYPE
    CHECK (
        UPPER(BASKET_TYPE) IN (
            'ANY',
            'STANDARD',
            'LIVESTOCK',
            'MIXED'
        )
    );

ALTER TABLE config.DELIVERY_ZONE
    DROP CONSTRAINT IF EXISTS CK_DELIVERY_ZONE_STANDARD_METHOD;

ALTER TABLE config.DELIVERY_ZONE
    ADD CONSTRAINT CK_DELIVERY_ZONE_STANDARD_METHOD
    CHECK (
        STANDARD_FULFILMENT_METHOD IS NULL
        OR UPPER(STANDARD_FULFILMENT_METHOD) IN (
            'CARRIER',
            'LOCAL_DELIVERY',
            'COLLECTION',
            'ROUTE_DELIVERY',
            'MEET_POINT'
        )
    );

ALTER TABLE config.DELIVERY_ZONE
    DROP CONSTRAINT IF EXISTS CK_DELIVERY_ZONE_LIVESTOCK_METHOD;

ALTER TABLE config.DELIVERY_ZONE
    ADD CONSTRAINT CK_DELIVERY_ZONE_LIVESTOCK_METHOD
    CHECK (
        LIVESTOCK_FULFILMENT_METHOD IS NULL
        OR UPPER(LIVESTOCK_FULFILMENT_METHOD) IN (
            'CARRIER',
            'LOCAL_DELIVERY',
            'COLLECTION',
            'ROUTE_DELIVERY',
            'MEET_POINT'
        )
    );


--------------------------------------------------------------------------
-- UK POSTCODE DATASET SAFE REFRESH
--------------------------------------------------------------------------

CREATE UNLOGGED TABLE IF NOT EXISTS core.GB_POSTCODE_DIRECTORY_STAGE
(
    LIKE core.GB_POSTCODE_DIRECTORY
        INCLUDING DEFAULTS
        INCLUDING CONSTRAINTS
        INCLUDING INDEXES
);

COMMENT ON TABLE core.GB_POSTCODE_DIRECTORY_STAGE IS
'Staging copy of the GB postcode directory. New Code-Point Open releases are loaded and validated here before the live postcode directory is replaced atomically.';

CREATE TABLE IF NOT EXISTS config.POSTCODE_DATASET_RELEASE (
    IMPORT_ID                       BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    SOURCE                          VARCHAR(50) NOT NULL DEFAULT 'OS_CODE_POINT_OPEN',
    SOURCE_DATE                     DATE,
    SOURCE_CHECKSUM                 VARCHAR(64),
    DATABASE_NAME                   VARCHAR(100) NOT NULL,
    FILE_COUNT                      INTEGER NOT NULL DEFAULT 0,
    ROW_COUNT                       BIGINT,
    COORDINATE_ROW_COUNT            BIGINT,
    FIRST_POSTCODE                  VARCHAR(8),
    LAST_POSTCODE                   VARCHAR(8),
    STATUS                          VARCHAR(20) NOT NULL DEFAULT 'STAGING',
    STARTED_AT                      TIMESTAMPTZ NOT NULL DEFAULT now(),
    VALIDATED_AT                    TIMESTAMPTZ,
    PROMOTED_AT                     TIMESTAMPTZ,
    COMPLETED_AT                    TIMESTAMPTZ,
    ERROR_TEXT                      TEXT,

    CONSTRAINT CK_POSTCODE_DATASET_RELEASE_STATUS
        CHECK (
            UPPER(STATUS) IN (
                'STAGING',
                'VALIDATED',
                'PROMOTED',
                'COMPLETED',
                'FAILED'
            )
        )
);

COMMENT ON TABLE config.POSTCODE_DATASET_RELEASE IS
'Audit history for self-hosted postcode dataset refreshes, including validation and promotion status.';

COMMENT ON COLUMN config.POSTCODE_DATASET_RELEASE.SOURCE_DATE IS
'Published/effective date supplied for the imported postcode dataset.';

COMMENT ON COLUMN config.POSTCODE_DATASET_RELEASE.SOURCE_CHECKSUM IS
'SHA-256 checksum identifying the imported postcode dataset content.';

COMMENT ON COLUMN config.POSTCODE_DATASET_RELEASE.ROW_COUNT IS
'Validated number of unique postcode rows in staging before promotion.';

COMMENT ON COLUMN config.POSTCODE_DATASET_RELEASE.COORDINATE_ROW_COUNT IS
'Number of staged postcode rows containing both easting and northing coordinates.';

CREATE INDEX IF NOT EXISTS IX_POSTCODE_DATASET_RELEASE_HISTORY
    ON config.POSTCODE_DATASET_RELEASE (
        SOURCE,
        SOURCE_DATE DESC,
        STARTED_AT DESC
    );

--------------------------------------------------------------------------
-- API FUNCTIONS
--------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION api.GET_POSTCODE_DISTANCE (
    p_client_id VARCHAR,
    p_postcode TEXT
)
RETURNS JSONB
LANGUAGE plpgsql
STABLE
AS $$
DECLARE
    v_postcode_compact TEXT;
    v_origin_postcode TEXT;
    v_origin_compact TEXT;
    v_destination RECORD;
    v_origin RECORD;
    v_distance_miles NUMERIC(8,2);
BEGIN
    v_postcode_compact :=
        regexp_replace(
            UPPER(COALESCE(p_postcode,'')),
            '[[:space:]]',
            '',
            'g'
        );

    IF v_postcode_compact = ''
       OR length(v_postcode_compact) NOT BETWEEN 5 AND 7
       OR v_postcode_compact !~ '^[A-Z0-9]+$'
    THEN
        RETURN jsonb_build_object(
            'postcodeValid', FALSE,
            'distanceAvailable', FALSE,
            'code', 'DELIVERY_POSTCODE_INVALID'
        );
    END IF;

    SELECT
        postcode,
        postcode_compact,
        easting,
        northing
    INTO v_destination
    FROM core.gb_postcode_directory
    WHERE postcode_compact = v_postcode_compact
    LIMIT 1;

    IF NOT FOUND THEN
        RETURN jsonb_build_object(
            'postcodeValid', FALSE,
            'distanceAvailable', FALSE,
            'postcode', p_postcode,
            'code', 'DELIVERY_POSTCODE_NOT_FOUND'
        );
    END IF;

    IF v_destination.easting IS NULL
       OR v_destination.northing IS NULL
    THEN
        RETURN jsonb_build_object(
            'postcodeValid', TRUE,
            'distanceAvailable', FALSE,
            'postcode', v_destination.postcode,
            'code', 'DELIVERY_POSTCODE_COORDINATES_UNAVAILABLE'
        );
    END IF;

    SELECT value_text
    INTO v_origin_postcode
    FROM config.system_setting
    WHERE client_id = p_client_id
      AND site_id IS NULL
      AND setting_key = 'DELIVERY_ORIGIN_POSTCODE'
      AND active = TRUE
    ORDER BY setting_id DESC
    LIMIT 1;

    IF v_origin_postcode IS NULL
       OR btrim(v_origin_postcode) = ''
    THEN
        RETURN jsonb_build_object(
            'postcodeValid', TRUE,
            'distanceAvailable', FALSE,
            'postcode', v_destination.postcode,
            'code', 'DELIVERY_ORIGIN_NOT_CONFIGURED'
        );
    END IF;

    v_origin_compact :=
        regexp_replace(
            UPPER(v_origin_postcode),
            '[[:space:]]',
            '',
            'g'
        );

    SELECT
        postcode,
        postcode_compact,
        easting,
        northing
    INTO v_origin
    FROM core.gb_postcode_directory
    WHERE postcode_compact = v_origin_compact
    LIMIT 1;

    IF NOT FOUND
       OR v_origin.easting IS NULL
       OR v_origin.northing IS NULL
    THEN
        RETURN jsonb_build_object(
            'postcodeValid', TRUE,
            'distanceAvailable', FALSE,
            'postcode', v_destination.postcode,
            'originPostcode', v_origin_postcode,
            'code', 'DELIVERY_ORIGIN_INVALID'
        );
    END IF;

    v_distance_miles :=
        ROUND(
            (
                SQRT(
                    POWER(
                        (v_destination.easting - v_origin.easting)::NUMERIC,
                        2
                    )
                    +
                    POWER(
                        (v_destination.northing - v_origin.northing)::NUMERIC,
                        2
                    )
                )
                / 1609.344
            )::NUMERIC,
            2
        );

    RETURN jsonb_build_object(
        'postcodeValid', TRUE,
        'distanceAvailable', TRUE,
        'postcode', v_destination.postcode,
        'originPostcode', v_origin.postcode,
        'distanceMiles', v_distance_miles,
        'distanceBasis', 'POSTCODE_CENTROID_STRAIGHT_LINE'
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

CREATE OR REPLACE FUNCTION api.QUOTE_CHECKOUT(
    p_client_id VARCHAR,
    p_payload JSONB
)
RETURNS JSONB
LANGUAGE plpgsql
STABLE
AS $$
DECLARE
    v_delivery JSONB;
    v_basket JSONB;
    v_promo JSONB;
    v_discount NUMERIC := 0;
    v_total_before_delivery NUMERIC := 0;
    v_selected_code TEXT;
    v_selected JSONB;
    v_freight_cost NUMERIC;
    v_total NUMERIC;
    v_free_delivery BOOLEAN := FALSE;
    v_payment_ready BOOLEAN := FALSE;
BEGIN
    v_delivery := api.GET_DELIVERY_OPTIONS(p_client_id,p_payload);
    v_basket := v_delivery->'basket';

    IF NOT COALESCE((v_delivery->>'valid')::BOOLEAN,FALSE) THEN
        RETURN v_delivery;
    END IF;

    IF NULLIF(TRIM(p_payload->>'promoCode'),'') IS NOT NULL THEN
        v_promo := api.VALIDATE_PROMOTION(
            p_client_id,
            p_payload->>'promoCode',
            (v_basket->>'subtotal')::NUMERIC,
            NULL
        );

        IF NOT COALESCE((v_promo->>'valid')::BOOLEAN,FALSE) THEN
            RETURN jsonb_build_object(
                'valid',FALSE,
                'code','PROMOTION_INVALID',
                'basket',v_basket,
                'promotion',v_promo,
                'discountAmount',0,
                'totalBeforeDelivery',(v_basket->>'subtotal')::NUMERIC,
                'deliveryContext',v_delivery->'deliveryContext',
                'fulfilmentOptions',v_delivery->'fulfilmentOptions'
            );
        END IF;

        v_discount := COALESCE((v_promo->>'discountAmount')::NUMERIC,0);
        v_free_delivery := COALESCE((v_promo->>'freeDelivery')::BOOLEAN,FALSE);
    END IF;

    v_total_before_delivery :=
        GREATEST((v_basket->>'subtotal')::NUMERIC - v_discount,0);

    v_selected_code := NULLIF(TRIM(p_payload->>'fulfilmentOptionCode'),'');

    IF v_selected_code IS NOT NULL THEN
        SELECT e.value
          INTO v_selected
          FROM jsonb_array_elements(
              COALESCE(v_delivery->'fulfilmentOptions','[]'::jsonb)
          ) AS e(value)
         WHERE UPPER(e.value->>'code') = UPPER(v_selected_code)
         LIMIT 1;

        IF v_selected IS NULL THEN
            RETURN jsonb_build_object(
                'valid',FALSE,
                'code','FULFILMENT_OPTION_NOT_AVAILABLE',
                'basket',v_basket,
                'promotion',v_promo,
                'discountAmount',v_discount,
                'totalBeforeDelivery',v_total_before_delivery,
                'deliveryContext',v_delivery->'deliveryContext',
                'fulfilmentOptions',v_delivery->'fulfilmentOptions'
            );
        END IF;

        IF UPPER(COALESCE(v_selected->>'currency',v_basket->>'currency')) <>
           UPPER(COALESCE(v_basket->>'currency','GBP')) THEN
            RETURN jsonb_build_object(
                'valid',FALSE,
                'code','FULFILMENT_CURRENCY_MISMATCH',
                'basket',v_basket,
                'promotion',v_promo,
                'selectedFulfilmentOption',v_selected,
                'deliveryContext',v_delivery->'deliveryContext',
                'fulfilmentOptions',v_delivery->'fulfilmentOptions'
            );
        END IF;

        IF jsonb_typeof(v_selected->'price') = 'number' THEN
            v_payment_ready := TRUE;
            v_freight_cost :=
                CASE
                    WHEN v_free_delivery THEN 0
                    ELSE (v_selected->>'price')::NUMERIC
                END;
            v_total := v_total_before_delivery + v_freight_cost;
        END IF;
    END IF;

    RETURN jsonb_build_object(
        'valid',TRUE,
        'basket',v_basket,
        'promotion',v_promo,
        'discountAmount',v_discount,
        'totalBeforeDelivery',v_total_before_delivery,
        'deliveryContext',v_delivery->'deliveryContext',
                'fulfilmentOptions',v_delivery->'fulfilmentOptions',
        'selectedFulfilmentOption',v_selected,
        'freightCost',v_freight_cost,
        'freeDelivery',v_free_delivery,
        'paymentReady',v_payment_ready,
        'total',v_total
    );
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
            'fulfilmentOptionCode',v_existing_order.SERVICE_LEVEL,
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
           SERVICE_LEVEL=v_fulfilment_option_code,
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

--------------------------------------------------------------------------
-- RELEASE VERSION
--------------------------------------------------------------------------

UPDATE config.SYSTEM_VERSION
SET IS_CURRENT=FALSE
WHERE PRODUCT_CODE='DYNETIC_WMS'
  AND IS_CURRENT=TRUE
  AND VERSION_NUMBER <> '0.3.11';

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
    '0.3.11',
    0,
    3,
    11,
    0,
    'RELEASE',
    CURRENT_DATE,
    'Add postcode-distance delivery rules, mixed fulfilment plans and safe staged Code-Point refresh.',
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