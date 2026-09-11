CREATE TABLE IF NOT EXISTS interface.ORDER_LINE_IF (
    INTERFACE_ID         uuid NOT NULL REFERENCES interface.ORDER_HEADER_IF(INTERFACE_ID) ON DELETE CASCADE,
    LINE_ID              numeric(6) NOT NULL,
    SOURCE_LINE_ID       varchar(100),
    SKU_ID               varchar(50) NOT NULL,
    QTY_ORDERED          numeric(15,6) NOT NULL,
    PRODUCT_PRICE        numeric(12,3),
    EXTENDED_PRICE       numeric(12,3),
    NOTES                varchar(80),
    PROCESS_STATUS       varchar(30) NOT NULL DEFAULT 'NEW',
    ERROR_CODE           varchar(50),
    ERROR_TEXT           text,
    CREATED_DSTAMP       timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (INTERFACE_ID, LINE_ID)
);
