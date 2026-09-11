CREATE TABLE IF NOT EXISTS audit.RULE_DECISION_LOG (
    DECISION_ID bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    CLIENT_ID varchar(30),
    ENGINE_NAME varchar(50) NOT NULL,
    ENTITY_TYPE varchar(50),
    ENTITY_ID varchar(120),
    RULE_ID bigint,
    RULE_NAME varchar(120),
    MATCHED boolean,
    DECISION varchar(80),
    REASON text,
    DETAIL jsonb,
    CREATED_DSTAMP timestamptz NOT NULL DEFAULT now()
);
