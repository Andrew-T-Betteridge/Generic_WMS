CREATE OR REPLACE FUNCTION config.MERGE_CONDITION_MATCH (
    p_rule_id BIGINT,
    p_same_order BOOLEAN,
    p_same_customer BOOLEAN,
    p_same_postcode BOOLEAN,
    p_same_country BOOLEAN,
    p_same_delivery_class BOOLEAN,
    p_left_delivery_class VARCHAR,
    p_right_delivery_class VARCHAR,
    p_same_fulfilment_method BOOLEAN,
    p_fulfilment_method VARCHAR,
    p_combined_weight_kg NUMERIC,
    p_combined_volume_cm3 NUMERIC,
    p_any_held BOOLEAN,
    p_both_held BOOLEAN,
    p_fulfilment_preference VARCHAR
)
RETURNS BOOLEAN
LANGUAGE plpgsql
STABLE
AS $$
DECLARE
    r RECORD;
    v_group INTEGER;
    v_group_match BOOLEAN;
    v_match BOOLEAN;
    v_text TEXT;
    v_num NUMERIC;
    v_bool BOOLEAN;
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM config.MERGE_RULE_CONDITION
        WHERE RULE_ID=p_rule_id
    ) THEN
        RETURN TRUE;
    END IF;

    FOR v_group IN
        SELECT DISTINCT CONDITION_GROUP
        FROM config.MERGE_RULE_CONDITION
        WHERE RULE_ID=p_rule_id
        ORDER BY CONDITION_GROUP
    LOOP
        v_group_match := TRUE;

        FOR r IN
            SELECT *
            FROM config.MERGE_RULE_CONDITION
            WHERE RULE_ID=p_rule_id
              AND CONDITION_GROUP=v_group
            ORDER BY SEQUENCE,CONDITION_ID
        LOOP
            v_text := NULL;
            v_num := NULL;
            v_bool := NULL;
            v_match := FALSE;

            CASE UPPER(r.FIELD_NAME)
                WHEN 'SAME_ORDER' THEN v_bool := p_same_order;
                WHEN 'SAME_CUSTOMER' THEN v_bool := p_same_customer;
                WHEN 'SAME_POSTCODE' THEN v_bool := p_same_postcode;
                WHEN 'SAME_COUNTRY' THEN v_bool := p_same_country;
                WHEN 'SAME_DELIVERY_CLASS' THEN v_bool := p_same_delivery_class;
                WHEN 'LEFT_DELIVERY_CLASS' THEN v_text := p_left_delivery_class;
                WHEN 'RIGHT_DELIVERY_CLASS' THEN v_text := p_right_delivery_class;
                WHEN 'SAME_FULFILMENT_METHOD' THEN v_bool := p_same_fulfilment_method;
                WHEN 'FULFILMENT_METHOD' THEN v_text := p_fulfilment_method;
                WHEN 'COMBINED_WEIGHT_KG' THEN v_num := p_combined_weight_kg;
                WHEN 'COMBINED_VOLUME_CM3' THEN v_num := p_combined_volume_cm3;
                WHEN 'ANY_HELD' THEN v_bool := p_any_held;
                WHEN 'BOTH_HELD' THEN v_bool := p_both_held;
                WHEN 'FULFILMENT_PREFERENCE' THEN v_text := p_fulfilment_preference;
                ELSE
                    RAISE EXCEPTION
                        'Unsupported merge condition FIELD_NAME: %',
                        r.FIELD_NAME;
            END CASE;

            IF UPPER(r.OPERATOR)='EQ' THEN
                IF v_num IS NOT NULL THEN
                    v_match := v_num=r.VALUE_NUMERIC;
                ELSIF v_bool IS NOT NULL THEN
                    v_match := v_bool=r.VALUE_BOOLEAN;
                ELSE
                    v_match := UPPER(COALESCE(v_text,''))=
                               UPPER(COALESCE(r.VALUE_TEXT,''));
                END IF;

            ELSIF UPPER(r.OPERATOR)='NE' THEN
                IF v_num IS NOT NULL THEN
                    v_match := v_num<>r.VALUE_NUMERIC;
                ELSIF v_bool IS NOT NULL THEN
                    v_match := v_bool<>r.VALUE_BOOLEAN;
                ELSE
                    v_match := UPPER(COALESCE(v_text,''))<>
                               UPPER(COALESCE(r.VALUE_TEXT,''));
                END IF;

            ELSIF UPPER(r.OPERATOR)='GT' THEN
                v_match := v_num>r.VALUE_NUMERIC;

            ELSIF UPPER(r.OPERATOR)='GTE' THEN
                v_match := v_num>=r.VALUE_NUMERIC;

            ELSIF UPPER(r.OPERATOR)='LT' THEN
                v_match := v_num<r.VALUE_NUMERIC;

            ELSIF UPPER(r.OPERATOR)='LTE' THEN
                v_match := v_num<=r.VALUE_NUMERIC;

            ELSIF UPPER(r.OPERATOR)='BETWEEN' THEN
                v_match := v_num BETWEEN r.VALUE_FROM AND r.VALUE_TO;

            ELSIF UPPER(r.OPERATOR)='IN' THEN
                v_match := UPPER(COALESCE(v_text,'')) = ANY(
                    string_to_array(
                        UPPER(REPLACE(COALESCE(r.VALUE_TEXT,''),' ','')),
                        ','
                    )
                );

            ELSIF UPPER(r.OPERATOR)='IS_TRUE' THEN
                v_match := COALESCE(v_bool,FALSE)=TRUE;

            ELSIF UPPER(r.OPERATOR)='IS_FALSE' THEN
                v_match := COALESCE(v_bool,FALSE)=FALSE;

            ELSE
                RAISE EXCEPTION
                    'Unsupported merge condition OPERATOR: %',
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

        IF v_group_match THEN
            RETURN TRUE;
        END IF;
    END LOOP;

    RETURN FALSE;
END;
$$;
