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