\set ON_ERROR_STOP on

-- DYNETIC_TEST_ENVIRONMENT_GUARD_BEGIN
DO $dynetic_test_guard$
DECLARE
    v_database text := current_database();
BEGIN
    IF v_database NOT IN ('fulfilment_dev', 'fulfilment_test') THEN
        RAISE EXCEPTION
            'SAFETY STOP: database test execution is forbidden against database "%". Only fulfilment_dev and fulfilment_test are allowed.',
            v_database;
    END IF;

    RAISE NOTICE 'SAFETY: test database verified as %', v_database;
END
$dynetic_test_guard$;
-- DYNETIC_TEST_ENVIRONMENT_GUARD_END
BEGIN;

INSERT INTO core.CLIENT (CLIENT_ID,DESCRIPTION,ACTIVE)
VALUES ('MERGEEDGE','Merge Edge Test',TRUE)
ON CONFLICT (CLIENT_ID) DO NOTHING;

INSERT INTO core.ORDER_HEADER (
    CLIENT_ID,ORDER_ID,ORDER_DATE,ORDER_VALUE,INV_CURRENCY,
    FREE_DELIVERY,FULFILMENT_PREFERENCE
)
VALUES
    ('MERGEEDGE','EDGE-1',now(),40,'GBP','N','SPLIT_WHEN_REQUIRED'),
    ('MERGEEDGE','EDGE-2',now(),40,'GBP','N','CONSOLIDATE');

INSERT INTO core.ORDER_CONTAINER (
    CLIENT_ID,ORDER_ID,CONTAINER_ID,STATUS,WEIGHT,VOLUME,
    DELIVERY_CLASS,FULFILMENT_METHOD,HOLD_STATUS,HOLD_REASON,HOLD_SOURCE
)
VALUES
    ('MERGEEDGE','EDGE-1','EDGE-FISH','PACKED',2,2000,
     'LIVESTOCK','CARRIER','DELIVERY_HOLD','Weather/operational hold','TEST'),
    ('MERGEEDGE','EDGE-1','EDGE-DRY','PACKED',1,1000,
     'STANDARD','CARRIER','NONE',NULL,NULL),
    ('MERGEEDGE','EDGE-2','EDGE-LIVE-2','PACKED',2,2000,
     'LIVESTOCK','LOCAL_DELIVERY','NONE',NULL,NULL),
    ('MERGEEDGE','EDGE-2','EDGE-DRY-2','PACKED',1,1000,
     'STANDARD','LOCAL_DELIVERY','NONE',NULL,NULL);

-- Held livestock and releasable dry goods must never auto-merge.
DO $$
DECLARE v_allowed BOOLEAN;
BEGIN
    SELECT RESULT_ALLOWED
    INTO v_allowed
    FROM core.EVALUATE_CONTAINER_MERGE(
        'MERGEEDGE','EDGE-FISH','EDGE-DRY'
    );

    IF v_allowed THEN
        RAISE EXCEPTION
            'Held and releasable containers must not merge.';
    END IF;
END
$$;

-- Mixed delivery classes are rejected unless explicitly allowed.
DO $$
DECLARE v_allowed BOOLEAN;
BEGIN
    SELECT RESULT_ALLOWED
    INTO v_allowed
    FROM core.EVALUATE_CONTAINER_MERGE(
        'MERGEEDGE','EDGE-LIVE-2','EDGE-DRY-2'
    );

    IF v_allowed THEN
        RAISE EXCEPTION
            'Mixed delivery classes require an explicit ALLOW rule.';
    END IF;
END
$$;

-- Explicitly allow mixed classes for LOCAL_DELIVERY on consolidated orders.
INSERT INTO config.MERGE_RULE (
    CLIENT_ID,RULE_NAME,PRIORITY,ACTIVE,DECISION,STOP_ON_MATCH
)
VALUES (
    'MERGEEDGE','ALLOW MIXED LOCAL DELIVERY',10,TRUE,'ALLOW',TRUE
);

INSERT INTO config.MERGE_RULE_CONDITION (
    RULE_ID,FIELD_NAME,OPERATOR,VALUE_TEXT,
    CONDITION_GROUP,SEQUENCE
)
SELECT RULE_ID,'FULFILMENT_METHOD','EQ','LOCAL_DELIVERY',1,10
FROM config.MERGE_RULE
WHERE CLIENT_ID='MERGEEDGE'
  AND RULE_NAME='ALLOW MIXED LOCAL DELIVERY';

INSERT INTO config.MERGE_RULE_CONDITION (
    RULE_ID,FIELD_NAME,OPERATOR,VALUE_TEXT,
    CONDITION_GROUP,SEQUENCE
)
SELECT RULE_ID,'FULFILMENT_PREFERENCE','EQ','CONSOLIDATE',1,20
FROM config.MERGE_RULE
WHERE CLIENT_ID='MERGEEDGE'
  AND RULE_NAME='ALLOW MIXED LOCAL DELIVERY';

DO $$
DECLARE v_allowed BOOLEAN;
BEGIN
    SELECT RESULT_ALLOWED
    INTO v_allowed
    FROM core.EVALUATE_CONTAINER_MERGE(
        'MERGEEDGE','EDGE-LIVE-2','EDGE-DRY-2'
    );

    IF NOT v_allowed THEN
        RAISE EXCEPTION
            'Explicit mixed local-delivery merge rule should allow consolidation.';
    END IF;
END
$$;

-- Cross-order merge remains deliberately rejected in V1.
DO $$
DECLARE v_allowed BOOLEAN;
BEGIN
    SELECT RESULT_ALLOWED
    INTO v_allowed
    FROM core.EVALUATE_CONTAINER_MERGE(
        'MERGEEDGE','EDGE-DRY','EDGE-DRY-2'
    );

    IF v_allowed THEN
        RAISE EXCEPTION
            'Cross-order merge should be rejected in Merge V1.';
    END IF;
END
$$;

ROLLBACK;
