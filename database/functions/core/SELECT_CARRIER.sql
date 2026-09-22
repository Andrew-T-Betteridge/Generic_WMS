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
