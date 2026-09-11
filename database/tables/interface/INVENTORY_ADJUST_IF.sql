CREATE TABLE IF NOT EXISTS interface.INVENTORY_ADJUST_IF (
    INTERFACE_ID         uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    CLIENT_ID            varchar(10) NOT NULL,
    SOURCE_SYSTEM        varchar(50) NOT NULL,
    SOURCE_REFERENCE     varchar(100) NOT NULL,
    SKU_ID               varchar(50) NOT NULL,
    LOCATION_ID          varchar(20),
    TAG_ID               varchar(50),
    ADJUSTMENT_QTY       numeric(15,6) NOT NULL,
    REASON_CODE          varchar(50),
    NOTES                text,
    PROCESS_STATUS       varchar(30) NOT NULL DEFAULT 'NEW',
    ERROR_CODE           varchar(50),
    ERROR_TEXT           text,
    CREATED_DSTAMP       timestamptz NOT NULL DEFAULT now(),
    PROCESSED_DSTAMP     timestamptz,
    UNIQUE (CLIENT_ID, SOURCE_SYSTEM, SOURCE_REFERENCE),
    FOREIGN KEY (CLIENT_ID) REFERENCES core.CLIENT(CLIENT_ID)
);
