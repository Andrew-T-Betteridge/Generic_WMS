CREATE TABLE IF NOT EXISTS interface.PRE_ADVICE_HEADER_IF (
    INTERFACE_ID         uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    CLIENT_ID            varchar(10) NOT NULL,
    SOURCE_SYSTEM        varchar(50) NOT NULL,
    SOURCE_REFERENCE     varchar(100) NOT NULL,
    PRE_ADVICE_ID        varchar(50),
    SITE_ID              varchar(30),
    SUPPLIER_ID          varchar(50),
    DUE_DSTAMP           timestamptz,
    PROCESS_STATUS       varchar(30) NOT NULL DEFAULT 'NEW',
    ERROR_CODE           varchar(50),
    ERROR_TEXT           text,
    CREATED_DSTAMP       timestamptz NOT NULL DEFAULT now(),
    PROCESSED_DSTAMP     timestamptz,
    UNIQUE (CLIENT_ID, SOURCE_SYSTEM, SOURCE_REFERENCE),
    FOREIGN KEY (CLIENT_ID) REFERENCES core.CLIENT(CLIENT_ID)
);
