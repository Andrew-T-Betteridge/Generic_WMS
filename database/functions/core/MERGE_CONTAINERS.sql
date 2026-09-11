CREATE OR REPLACE FUNCTION core.MERGE_CONTAINERS (
    p_client_id VARCHAR,
    p_target_container_id VARCHAR,
    p_source_container_id VARCHAR,
    p_user_id VARCHAR DEFAULT 'SYSTEM'
)
RETURNS TABLE (
    RESULT_STATUS VARCHAR,
    RESULT_TARGET_CONTAINER_ID VARCHAR,
    RESULT_SOURCE_CONTAINER_ID VARCHAR,
    RESULT_MESSAGE TEXT
)
LANGUAGE plpgsql
AS $$
DECLARE
    v_eval RECORD;
    v_target RECORD;
    v_source RECORD;
    v_user VARCHAR(20) := LEFT(COALESCE(NULLIF(p_user_id,''),'SYSTEM'),20);
BEGIN
    -- Lock in deterministic order to reduce deadlock risk.
    PERFORM 1
    FROM core.ORDER_CONTAINER
    WHERE CLIENT_ID=p_client_id
      AND CONTAINER_ID IN (p_target_container_id,p_source_container_id)
    ORDER BY CONTAINER_ID
    FOR UPDATE;

    SELECT *
    INTO v_eval
    FROM core.EVALUATE_CONTAINER_MERGE(
        p_client_id,p_target_container_id,p_source_container_id
    );

    IF NOT COALESCE(v_eval.RESULT_ALLOWED,FALSE) THEN
        INSERT INTO audit.RULE_DECISION_LOG (
            CLIENT_ID,ENGINE_NAME,ENTITY_TYPE,ENTITY_ID,
            RULE_ID,RULE_NAME,MATCHED,DECISION,REASON,DETAIL
        )
        VALUES (
            p_client_id,
            'CONTAINER_MERGE',
            'ORDER_CONTAINER',
            p_source_container_id,
            v_eval.RESULT_RULE_ID,
            v_eval.RESULT_RULE_NAME,
            v_eval.RESULT_RULE_ID IS NOT NULL,
            'REJECTED',
            v_eval.RESULT_REASON,
            jsonb_build_object(
                'target_container_id',p_target_container_id,
                'source_container_id',p_source_container_id,
                'user_id',v_user
            )
        );

        RETURN QUERY
        SELECT
            'REJECTED'::VARCHAR,
            p_target_container_id::VARCHAR,
            p_source_container_id::VARCHAR,
            v_eval.RESULT_REASON::TEXT;
        RETURN;
    END IF;

    SELECT *
    INTO v_target
    FROM core.ORDER_CONTAINER
    WHERE CLIENT_ID=p_client_id
      AND CONTAINER_ID=p_target_container_id;

    SELECT *
    INTO v_source
    FROM core.ORDER_CONTAINER
    WHERE CLIENT_ID=p_client_id
      AND CONTAINER_ID=p_source_container_id;

    -- Move packed contents to the surviving physical/logical container.
    UPDATE core.SHIPPING_MANIFEST
    SET CONTAINER_ID=p_target_container_id,
        CARRIER_ID=NULL,
        SERVICE_LEVEL=NULL,
        CARRIER_SELECTION_RULE_ID=NULL
    WHERE CLIENT_ID=p_client_id
      AND CONTAINER_ID=p_source_container_id
      AND COALESCE(QTY_SHIPPED,0)=0;

    -- Weight/volume are additive. Physical dimensions are deliberately not
    -- mathematically combined because the surviving package determines them.
    UPDATE core.ORDER_CONTAINER
    SET WEIGHT=COALESCE(v_target.WEIGHT,0)+COALESCE(v_source.WEIGHT,0),
        VOLUME=COALESCE(v_target.VOLUME,0)+COALESCE(v_source.VOLUME,0),
        CARRIER_ID=NULL,
        SERVICE_LEVEL=NULL,
        CARRIER_COST=NULL,
        CARRIER_SELECTION_SOURCE=NULL,
        CARRIER_SELECTION_RULE_ID=NULL,
        CARRIER_SELECTED_DSTAMP=NULL,
        CARRIER_OVERRIDE_REASON=NULL,
        MERGE_RULE_ID=v_eval.RESULT_RULE_ID
    WHERE CLIENT_ID=p_client_id
      AND CONTAINER_ID=p_target_container_id;

    UPDATE core.ORDER_CONTAINER
    SET STATUS='MERGED',
        MERGED_INTO_CONTAINER_ID=p_target_container_id,
        MERGED_DSTAMP=now(),
        MERGED_BY=v_user,
        MERGE_RULE_ID=v_eval.RESULT_RULE_ID
    WHERE CLIENT_ID=p_client_id
      AND CONTAINER_ID=p_source_container_id;

    INSERT INTO audit.RULE_DECISION_LOG (
        CLIENT_ID,ENGINE_NAME,ENTITY_TYPE,ENTITY_ID,
        RULE_ID,RULE_NAME,MATCHED,DECISION,REASON,DETAIL
    )
    VALUES (
        p_client_id,
        'CONTAINER_MERGE',
        'ORDER_CONTAINER',
        p_source_container_id,
        v_eval.RESULT_RULE_ID,
        v_eval.RESULT_RULE_NAME,
        v_eval.RESULT_RULE_ID IS NOT NULL,
        'MERGED',
        v_eval.RESULT_REASON,
        jsonb_build_object(
            'target_container_id',p_target_container_id,
            'source_container_id',p_source_container_id,
            'combined_weight',COALESCE(v_target.WEIGHT,0)+COALESCE(v_source.WEIGHT,0),
            'combined_volume',COALESCE(v_target.VOLUME,0)+COALESCE(v_source.VOLUME,0),
            'carrier_selection_reset',TRUE,
            'user_id',v_user
        )
    );

    RETURN QUERY
    SELECT
        'MERGED'::VARCHAR,
        p_target_container_id::VARCHAR,
        p_source_container_id::VARCHAR,
        'Containers merged. Carrier selection must be run again for the surviving container.'::TEXT;
END;
$$;
