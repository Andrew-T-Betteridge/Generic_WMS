CREATE TABLE IF NOT EXISTS interface.PRE_ADVICE_LINE_IF (
    INTERFACE_ID         uuid NOT NULL REFERENCES interface.PRE_ADVICE_HEADER_IF(INTERFACE_ID) ON DELETE CASCADE,
    LINE_ID              numeric(6) NOT NULL,
    SKU_ID               varchar(50) NOT NULL,
    QTY_DUE              numeric(15,6) NOT NULL,
    BATCH_ID             varchar(50),
    EXPIRY_DSTAMP        timestamptz,
    PROCESS_STATUS       varchar(30) NOT NULL DEFAULT 'NEW',
    ERROR_CODE           varchar(50),
    ERROR_TEXT           text,
    CREATED_DSTAMP       timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (INTERFACE_ID, LINE_ID)
);
