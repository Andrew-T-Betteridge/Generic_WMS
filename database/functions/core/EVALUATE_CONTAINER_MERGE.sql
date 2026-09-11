CREATE OR REPLACE FUNCTION core.EVALUATE_CONTAINER_MERGE (
    p_client_id VARCHAR,
    p_left_container_id VARCHAR,
    p_right_container_id VARCHAR
)
RETURNS TABLE (
    RESULT_STATUS VARCHAR,
    RESULT_ALLOWED BOOLEAN,
    RESULT_RULE_ID BIGINT,
    RESULT_RULE_NAME VARCHAR,
    RESULT_REASON TEXT
)
LANGUAGE plpgsql
STABLE
AS $$
DECLARE
    l RECORD;
    r RECORD;
    mr RECORD;
    v_same_order BOOLEAN;
    v_same_customer BOOLEAN;
    v_same_postcode BOOLEAN;
    v_same_country BOOLEAN;
    v_same_class BOOLEAN;
    v_same_method BOOLEAN;
    v_any_held BOOLEAN;
    v_both_held BOOLEAN;
    v_combined_weight NUMERIC;
    v_combined_volume NUMERIC;
BEGIN
    IF p_left_container_id=p_right_container_id THEN
        RETURN QUERY
        SELECT 'REJECTED'::VARCHAR,FALSE,NULL::BIGINT,NULL::VARCHAR,
               'A container cannot be merged into itself.'::TEXT;
        RETURN;
    END IF;

    SELECT
        oc.*,
        hdr.CUSTOMER_ID,
        hdr.POSTCODE,
        hdr.COUNTRY,
        hdr.FULFILMENT_PREFERENCE
    INTO l
    FROM core.ORDER_CONTAINER oc
    JOIN core.ORDER_HEADER hdr
      ON hdr.CLIENT_ID=oc.CLIENT_ID
     AND hdr.ORDER_ID=oc.ORDER_ID
    WHERE oc.CLIENT_ID=p_client_id
      AND oc.CONTAINER_ID=p_left_container_id;

    IF NOT FOUND THEN
        RETURN QUERY
        SELECT 'ERROR'::VARCHAR,FALSE,NULL::BIGINT,NULL::VARCHAR,
               'Left container does not exist.'::TEXT;
        RETURN;
    END IF;

    SELECT
        oc.*,
        hdr.CUSTOMER_ID,
        hdr.POSTCODE,
        hdr.COUNTRY,
        hdr.FULFILMENT_PREFERENCE
    INTO r
    FROM core.ORDER_CONTAINER oc
    JOIN core.ORDER_HEADER hdr
      ON hdr.CLIENT_ID=oc.CLIENT_ID
     AND hdr.ORDER_ID=oc.ORDER_ID
    WHERE oc.CLIENT_ID=p_client_id
      AND oc.CONTAINER_ID=p_right_container_id;

    IF NOT FOUND THEN
        RETURN QUERY
        SELECT 'ERROR'::VARCHAR,FALSE,NULL::BIGINT,NULL::VARCHAR,
               'Right container does not exist.'::TEXT;
        RETURN;
    END IF;

    -- V1 deliberately supports same-order consolidation only.
    IF l.ORDER_ID<>r.ORDER_ID THEN
        RETURN QUERY
        SELECT 'REJECTED'::VARCHAR,FALSE,NULL::BIGINT,NULL::VARCHAR,
               'Merge V1 only consolidates containers belonging to the same order.'::TEXT;
        RETURN;
    END IF;

    IF UPPER(COALESCE(l.STATUS,'')) IN ('SHIPPED','MERGED','CANCELLED')
       OR UPPER(COALESCE(r.STATUS,'')) IN ('SHIPPED','MERGED','CANCELLED')
    THEN
        RETURN QUERY
        SELECT 'REJECTED'::VARCHAR,FALSE,NULL::BIGINT,NULL::VARCHAR,
               'Shipped, merged or cancelled containers cannot be merged.'::TEXT;
        RETURN;
    END IF;

    IF EXISTS (
        SELECT 1
        FROM core.SHIPPING_MANIFEST sm
        WHERE sm.CLIENT_ID=p_client_id
          AND sm.CONTAINER_ID IN (p_left_container_id,p_right_container_id)
          AND COALESCE(sm.QTY_SHIPPED,0)>0
    ) THEN
        RETURN QUERY
        SELECT 'REJECTED'::VARCHAR,FALSE,NULL::BIGINT,NULL::VARCHAR,
               'A container with shipped quantity cannot be merged.'::TEXT;
        RETURN;
    END IF;

    v_same_order := l.ORDER_ID=r.ORDER_ID;
    v_same_customer := COALESCE(l.CUSTOMER_ID,'')=COALESCE(r.CUSTOMER_ID,'');
    v_same_postcode := COALESCE(UPPER(l.POSTCODE),'')=COALESCE(UPPER(r.POSTCODE),'');
    v_same_country := COALESCE(UPPER(l.COUNTRY),'')=COALESCE(UPPER(r.COUNTRY),'');
    v_same_class := UPPER(COALESCE(l.DELIVERY_CLASS,'STANDARD'))=
                    UPPER(COALESCE(r.DELIVERY_CLASS,'STANDARD'));
    v_same_method := UPPER(COALESCE(l.FULFILMENT_METHOD,'CARRIER'))=
                     UPPER(COALESCE(r.FULFILMENT_METHOD,'CARRIER'));
    v_any_held := COALESCE(l.HOLD_STATUS,'NONE')<>'NONE'
                  OR COALESCE(r.HOLD_STATUS,'NONE')<>'NONE';
    v_both_held := COALESCE(l.HOLD_STATUS,'NONE')<>'NONE'
                   AND COALESCE(r.HOLD_STATUS,'NONE')<>'NONE';
    v_combined_weight := COALESCE(l.WEIGHT,0)+COALESCE(r.WEIGHT,0);
    v_combined_volume := COALESCE(l.VOLUME,0)+COALESCE(r.VOLUME,0);

    IF NOT v_same_method THEN
        RETURN QUERY
        SELECT 'REJECTED'::VARCHAR,FALSE,NULL::BIGINT,NULL::VARCHAR,
               'Containers use different fulfilment methods.'::TEXT;
        RETURN;
    END IF;

    IF COALESCE(l.HOLD_STATUS,'NONE')<>COALESCE(r.HOLD_STATUS,'NONE') THEN
        RETURN QUERY
        SELECT 'REJECTED'::VARCHAR,FALSE,NULL::BIGINT,NULL::VARCHAR,
               'Held and releasable containers are not merged automatically.'::TEXT;
        RETURN;
    END IF;

    IF COALESCE(l.CARRIER_ID,'')<>'' AND COALESCE(r.CARRIER_ID,'')<>''
       AND l.CARRIER_ID<>r.CARRIER_ID
    THEN
        RETURN QUERY
        SELECT 'REJECTED'::VARCHAR,FALSE,NULL::BIGINT,NULL::VARCHAR,
               'Containers already have different carriers selected.'::TEXT;
        RETURN;
    END IF;

    IF COALESCE(l.SERVICE_LEVEL,'')<>'' AND COALESCE(r.SERVICE_LEVEL,'')<>''
       AND l.SERVICE_LEVEL<>r.SERVICE_LEVEL
    THEN
        RETURN QUERY
        SELECT 'REJECTED'::VARCHAR,FALSE,NULL::BIGINT,NULL::VARCHAR,
               'Containers already have different carrier service levels.'::TEXT;
        RETURN;
    END IF;

    FOR mr IN
        SELECT m.*
        FROM config.MERGE_RULE m
        WHERE m.CLIENT_ID=p_client_id
          AND m.ACTIVE=TRUE
        ORDER BY m.PRIORITY,m.RULE_ID
    LOOP
        IF config.MERGE_CONDITION_MATCH(
            mr.RULE_ID,
            v_same_order,
            v_same_customer,
            v_same_postcode,
            v_same_country,
            v_same_class,
            UPPER(COALESCE(l.DELIVERY_CLASS,'STANDARD')),
            UPPER(COALESCE(r.DELIVERY_CLASS,'STANDARD')),
            v_same_method,
            UPPER(COALESCE(l.FULFILMENT_METHOD,'CARRIER')),
            v_combined_weight,
            v_combined_volume,
            v_any_held,
            v_both_held,
            l.FULFILMENT_PREFERENCE
        ) THEN
            RETURN QUERY
            SELECT
                CASE WHEN mr.DECISION='ALLOW'
                     THEN 'ALLOWED' ELSE 'REJECTED' END::VARCHAR,
                (mr.DECISION='ALLOW'),
                mr.RULE_ID,
                mr.RULE_NAME,
                format('Matched merge rule %s (%s).',
                       mr.RULE_NAME,mr.DECISION)::TEXT;
            RETURN;
        END IF;
    END LOOP;

    IF v_same_class THEN
        RETURN QUERY
        SELECT 'ALLOWED'::VARCHAR,TRUE,NULL::BIGINT,NULL::VARCHAR,
               'Compatible same-order containers with the same delivery class.'::TEXT;
    ELSE
        RETURN QUERY
        SELECT 'REJECTED'::VARCHAR,FALSE,NULL::BIGINT,NULL::VARCHAR,
               'Different delivery classes require an explicit ALLOW merge rule.'::TEXT;
    END IF;
END;
$$;
