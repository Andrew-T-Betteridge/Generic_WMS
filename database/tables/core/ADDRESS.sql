-- ADDRESS
-- Generated from the previously refined FINatics_DB_Keep_Only.xlsx specification.
-- Generic WMS core: no fish-specific table naming.

CREATE TABLE IF NOT EXISTS core.ADDRESS (
    CLIENT_ID                      VARCHAR(10) NOT NULL,
    ADDRESS_ID                     VARCHAR(15) NOT NULL,
    ADDRESS_TYPE                   VARCHAR(10),
    CONTACT                        VARCHAR(25),
    CONTACT_PHONE                  VARCHAR(25),
    CONTACT_MOBILE                 VARCHAR(25),
    CONTACT_EMAIL                  VARCHAR(256),
    NAME                           VARCHAR(50),
    ADDRESS1                       VARCHAR(60),
    ADDRESS2                       VARCHAR(60),
    TOWN                           VARCHAR(60),
    COUNTY                         VARCHAR(60),
    POSTCODE                       VARCHAR(20),
    COUNTRY                        VARCHAR(25),
    DIRECTIONS                     VARCHAR(180),
    URL                            VARCHAR(250),
    VAT_NUMBER                     VARCHAR(20),
    DELIVERY_OPEN_TIME             TIMESTAMPTZ,
    DELIVERY_CLOSE_TIME            TIMESTAMPTZ,
    DELIVERY_OPEN_MON              VARCHAR(1),
    DELIVERY_OPEN_TUE              VARCHAR(1),
    DELIVERY_OPEN_WED              VARCHAR(1),
    DELIVERY_OPEN_THUR             VARCHAR(1),
    DELIVERY_OPEN_FRI              VARCHAR(1),
    DELIVERY_OPEN_SAT              VARCHAR(1),
    DELIVERY_OPEN_SUN              VARCHAR(1),
    FASTEST_CARRIER                VARCHAR(1),
    CHEAPEST_CARRIER               VARCHAR(1),
    FREIGHT_CHARGES                VARCHAR(10),
    CUSTOMER_TYPE                  VARCHAR(1),
    CREDIT_STATUS                  VARCHAR(1),
    CREDIT_DAYS                    NUMERIC(4),
    RETAILER_ID                    VARCHAR(15),
    LATITUDE                       NUMERIC(10,7),
    LONGITUDE                      NUMERIC(10,7),
    ACTIVE                         CHAR(1) NOT NULL,
    DEFAULT_BILLING                CHAR(1) NOT NULL,
    DEFAULT_DELIVERY               CHAR(1) NOT NULL,
    PRIMARY KEY (CLIENT_ID, ADDRESS_ID),
    FOREIGN KEY (CLIENT_ID) REFERENCES core.CLIENT (CLIENT_ID)
);

COMMENT ON COLUMN core.ADDRESS.CLIENT_ID IS 'KEEP: Client/business identifier';
COMMENT ON COLUMN core.ADDRESS.ADDRESS_ID IS 'KEEP: Customer/billing/delivery address snapshot';
COMMENT ON COLUMN core.ADDRESS.ADDRESS_TYPE IS 'KEEP: Customer/billing/delivery address snapshot';
COMMENT ON COLUMN core.ADDRESS.CONTACT IS 'KEEP: Customer/billing/delivery address snapshot';
COMMENT ON COLUMN core.ADDRESS.CONTACT_PHONE IS 'KEEP: Existing WMS field retained for FINatics';
COMMENT ON COLUMN core.ADDRESS.CONTACT_MOBILE IS 'KEEP: Existing WMS field retained for FINatics';
COMMENT ON COLUMN core.ADDRESS.CONTACT_EMAIL IS 'KEEP: Existing WMS field retained for FINatics';
COMMENT ON COLUMN core.ADDRESS.NAME IS 'KEEP: Customer/billing/delivery address snapshot';
COMMENT ON COLUMN core.ADDRESS.ADDRESS1 IS 'KEEP: Customer/billing/delivery address snapshot';
COMMENT ON COLUMN core.ADDRESS.ADDRESS2 IS 'KEEP: Customer/billing/delivery address snapshot';
COMMENT ON COLUMN core.ADDRESS.TOWN IS 'KEEP: Customer/billing/delivery address snapshot';
COMMENT ON COLUMN core.ADDRESS.COUNTY IS 'KEEP: Customer/billing/delivery address snapshot';
COMMENT ON COLUMN core.ADDRESS.POSTCODE IS 'KEEP: Customer/billing/delivery address snapshot';
COMMENT ON COLUMN core.ADDRESS.COUNTRY IS 'KEEP: Customer/billing/delivery address snapshot';
COMMENT ON COLUMN core.ADDRESS.DIRECTIONS IS 'KEEP: Existing WMS field retained for FINatics';
COMMENT ON COLUMN core.ADDRESS.URL IS 'KEEP: Existing WMS field retained for FINatics';
COMMENT ON COLUMN core.ADDRESS.VAT_NUMBER IS 'KEEP: Existing WMS field retained for FINatics';
COMMENT ON COLUMN core.ADDRESS.DELIVERY_OPEN_TIME IS 'KEEP: Existing WMS field retained for FINatics';
COMMENT ON COLUMN core.ADDRESS.DELIVERY_CLOSE_TIME IS 'KEEP: Existing WMS field retained for FINatics';
COMMENT ON COLUMN core.ADDRESS.DELIVERY_OPEN_MON IS 'KEEP: Existing WMS field retained for FINatics';
COMMENT ON COLUMN core.ADDRESS.DELIVERY_OPEN_TUE IS 'KEEP: Existing WMS field retained for FINatics';
COMMENT ON COLUMN core.ADDRESS.DELIVERY_OPEN_WED IS 'KEEP: Existing WMS field retained for FINatics';
COMMENT ON COLUMN core.ADDRESS.DELIVERY_OPEN_THUR IS 'KEEP: Existing WMS field retained for FINatics';
COMMENT ON COLUMN core.ADDRESS.DELIVERY_OPEN_FRI IS 'KEEP: Existing WMS field retained for FINatics';
COMMENT ON COLUMN core.ADDRESS.DELIVERY_OPEN_SAT IS 'KEEP: Existing WMS field retained for FINatics';
COMMENT ON COLUMN core.ADDRESS.DELIVERY_OPEN_SUN IS 'KEEP: Existing WMS field retained for FINatics';
COMMENT ON COLUMN core.ADDRESS.FASTEST_CARRIER IS 'KEEP: Existing WMS field retained for FINatics';
COMMENT ON COLUMN core.ADDRESS.CHEAPEST_CARRIER IS 'KEEP: Existing WMS field retained for FINatics';
COMMENT ON COLUMN core.ADDRESS.FREIGHT_CHARGES IS 'KEEP: Delivery/freight charge/cost';
COMMENT ON COLUMN core.ADDRESS.CUSTOMER_TYPE IS 'KEEP: Existing WMS field retained for FINatics';
COMMENT ON COLUMN core.ADDRESS.CREDIT_STATUS IS 'KEEP: Existing WMS field retained for FINatics';
COMMENT ON COLUMN core.ADDRESS.CREDIT_DAYS IS 'KEEP: Existing WMS field retained for FINatics';
COMMENT ON COLUMN core.ADDRESS.RETAILER_ID IS 'KEEP: Existing WMS field retained for FINatics';
COMMENT ON COLUMN core.ADDRESS.LATITUDE IS 'ADD: Cached latitude for distance-based delivery';
COMMENT ON COLUMN core.ADDRESS.LONGITUDE IS 'ADD: Cached longitude for distance-based delivery';
COMMENT ON COLUMN core.ADDRESS.ACTIVE IS 'ADD: Whether address record is active';
COMMENT ON COLUMN core.ADDRESS.DEFAULT_BILLING IS 'ADD: Default billing address flag';
COMMENT ON COLUMN core.ADDRESS.DEFAULT_DELIVERY IS 'ADD: Default delivery address flag';
