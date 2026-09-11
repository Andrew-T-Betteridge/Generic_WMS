CREATE OR REPLACE FUNCTION config.CARRIER_CONDITION_MATCH (
    p_rule_id BIGINT,
    p_weight_kg NUMERIC,
    p_volume_cm3 NUMERIC,
    p_order_value NUMERIC,
    p_delivery_class VARCHAR,
    p_dispatch_method VARCHAR,
    p_requested_service VARCHAR,
    p_country VARCHAR,
    p_postcode VARCHAR,
    p_free_delivery VARCHAR
)
RETURNS BOOLEAN
LANGUAGE plpgsql
STABLE
AS $$
DECLARE
    r RECORD;
    v_text TEXT;
    v_num NUMERIC;
    v_bool BOOLEAN;
    v_match BOOLEAN;
    v_group INTEGER;
    v_group_match BOOLEAN;
BEGIN
    -- No child conditions means the rule relies only on the direct
    -- columns on config.CARRIER_SELECTION_RULE.
    IF NOT EXISTS (
        SELECT 1
        FROM config.CARRIER_SELECTION_CONDITION
        WHERE RULE_ID = p_rule_id
    ) THEN
        RETURN TRUE;
    END IF;

    -- Conditions within the same CONDITION_GROUP are ANDed together.
    -- Different groups are ORed together.
    FOR v_group IN
        SELECT DISTINCT CONDITION_GROUP
        FROM config.CARRIER_SELECTION_CONDITION
        WHERE RULE_ID = p_rule_id
        ORDER BY CONDITION_GROUP
    LOOP
        v_group_match := TRUE;

        FOR r IN
            SELECT *
            FROM config.CARRIER_SELECTION_CONDITION
            WHERE RULE_ID = p_rule_id
              AND CONDITION_GROUP = v_group
            ORDER BY SEQUENCE, CONDITION_ID
        LOOP
            v_text := NULL;
            v_num := NULL;
            v_bool := NULL;
            v_match := FALSE;

            -- Resolve only known/safe fields.
            CASE UPPER(r.FIELD_NAME)
                WHEN 'WEIGHT_KG' THEN
                    v_num := p_weight_kg;
                WHEN 'VOLUME_CM3' THEN
                    v_num := p_volume_cm3;
                WHEN 'ORDER_VALUE' THEN
                    v_num := p_order_value;
                WHEN 'DELIVERY_CLASS' THEN
                    v_text := p_delivery_class;
                WHEN 'DISPATCH_METHOD' THEN
                    v_text := p_dispatch_method;
                WHEN 'SERVICE_LEVEL' THEN
                    v_text := p_requested_service;
                WHEN 'COUNTRY' THEN
                    v_text := p_country;
                WHEN 'POSTCODE' THEN
                    v_text := p_postcode;
                WHEN 'POSTCODE_PREFIX' THEN
                    v_text := p_postcode;
                WHEN 'FREE_DELIVERY' THEN
                    v_bool := UPPER(COALESCE(p_free_delivery,'N'))
                              IN ('Y','YES','TRUE','1');
                ELSE
                    RAISE EXCEPTION
                        'Unsupported carrier condition FIELD_NAME: %',
                        r.FIELD_NAME;
            END CASE;

            -- Operators are handled as PL/pgSQL statements rather than
            -- trying to place RAISE EXCEPTION inside a SQL CASE expression.
            IF UPPER(r.OPERATOR) = 'EQ' THEN
                IF v_num IS NOT NULL THEN
                    v_match := v_num = r.VALUE_NUMERIC;
                ELSIF v_bool IS NOT NULL THEN
                    v_match := v_bool = r.VALUE_BOOLEAN;
                ELSE
                    v_match := UPPER(COALESCE(v_text,'')) =
                               UPPER(COALESCE(r.VALUE_TEXT,''));
                END IF;

            ELSIF UPPER(r.OPERATOR) = 'NE' THEN
                IF v_num IS NOT NULL THEN
                    v_match := v_num <> r.VALUE_NUMERIC;
                ELSIF v_bool IS NOT NULL THEN
                    v_match := v_bool <> r.VALUE_BOOLEAN;
                ELSE
                    v_match := UPPER(COALESCE(v_text,'')) <>
                               UPPER(COALESCE(r.VALUE_TEXT,''));
                END IF;

            ELSIF UPPER(r.OPERATOR) = 'GT' THEN
                v_match := v_num > r.VALUE_NUMERIC;

            ELSIF UPPER(r.OPERATOR) = 'GTE' THEN
                v_match := v_num >= r.VALUE_NUMERIC;

            ELSIF UPPER(r.OPERATOR) = 'LT' THEN
                v_match := v_num < r.VALUE_NUMERIC;

            ELSIF UPPER(r.OPERATOR) = 'LTE' THEN
                v_match := v_num <= r.VALUE_NUMERIC;

            ELSIF UPPER(r.OPERATOR) = 'BETWEEN' THEN
                v_match := v_num BETWEEN r.VALUE_FROM AND r.VALUE_TO;

            ELSIF UPPER(r.OPERATOR) = 'IN' THEN
                v_match := UPPER(COALESCE(v_text,'')) = ANY(
                    string_to_array(
                        UPPER(REPLACE(COALESCE(r.VALUE_TEXT,''),' ','')),
                        ','
                    )
                );

            ELSIF UPPER(r.OPERATOR) = 'STARTS_WITH' THEN
                v_match := UPPER(COALESCE(v_text,'')) LIKE
                           UPPER(COALESCE(r.VALUE_TEXT,'')) || '%';

            ELSIF UPPER(r.OPERATOR) = 'IS_TRUE' THEN
                v_match := COALESCE(v_bool,FALSE) = TRUE;

            ELSIF UPPER(r.OPERATOR) = 'IS_FALSE' THEN
                v_match := COALESCE(v_bool,FALSE) = FALSE;

            ELSE
                RAISE EXCEPTION
                    'Unsupported carrier condition OPERATOR: %',
                    r.OPERATOR;
            END IF;

            IF COALESCE(r.NEGATE,FALSE) THEN
                v_match := NOT COALESCE(v_match,FALSE);
            END IF;

            IF NOT COALESCE(v_match,FALSE) THEN
                v_group_match := FALSE;
                EXIT;
            END IF;
        END LOOP;

        -- OR between groups: one fully-matched group is enough.
        IF v_group_match THEN
            RETURN TRUE;
        END IF;
    END LOOP;

    RETURN FALSE;
END;
$$;
