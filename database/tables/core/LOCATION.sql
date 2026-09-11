-- LOCATION
-- Generated from the previously refined FINatics_DB_Keep_Only.xlsx specification.
-- Generic WMS core: no fish-specific table naming.

CREATE TABLE IF NOT EXISTS core.LOCATION (
    SITE_ID                        VARCHAR(10),
    LOCATION_ID                    VARCHAR(20) NOT NULL,
    ZONE_1                         VARCHAR(10),
    SUBZONE_1                      VARCHAR(10),
    SUBZONE_2                      VARCHAR(10),
    STORAGE_CLASS                  VARCHAR(10),
    LOC_TYPE                       VARCHAR(15) NOT NULL,
    LOCK_STATUS                    VARCHAR(20) NOT NULL,
    VOLUME                         NUMERIC(13,6) NOT NULL,
    HEIGHT                         NUMERIC(15,6),
    DEPTH                          NUMERIC(7,3),
    WIDTH                          NUMERIC(7,3),
    WEIGHT                         NUMERIC(13,6),
    DISALLOW_ALLOC                 VARCHAR(1),
    COUNT_DSTAMP                   TIMESTAMPTZ,
    PICK_FACE                      VARCHAR(1),
    COUNT_NEEDED                   VARCHAR(1) NOT NULL,
    AISLE                          VARCHAR(20),
    BAY                            VARCHAR(20),
    LEVELS                         VARCHAR(20),
    POSITION                       VARCHAR(20),
    LOCALITY                       VARCHAR(10),
    MAX_UNITS_ON_LOC               NUMERIC(10),
    ID                             NUMERIC NOT NULL,
    DESCRIPTION                    VARCHAR(120),
    ACTIVE                         CHAR(1) NOT NULL,
    LIVESTOCK_ALLOWED              CHAR(1) NOT NULL,
    PRIMARY KEY (LOCATION_ID)
);

COMMENT ON COLUMN core.LOCATION.SITE_ID IS 'KEEP: Existing WMS field retained for FINatics';
COMMENT ON COLUMN core.LOCATION.LOCATION_ID IS 'KEEP: Inventory/location identifier';
COMMENT ON COLUMN core.LOCATION.ZONE_1 IS 'KEEP: Existing WMS field retained for FINatics';
COMMENT ON COLUMN core.LOCATION.SUBZONE_1 IS 'KEEP: Existing WMS field retained for FINatics';
COMMENT ON COLUMN core.LOCATION.SUBZONE_2 IS 'KEEP: Existing WMS field retained for FINatics';
COMMENT ON COLUMN core.LOCATION.STORAGE_CLASS IS 'KEEP: Existing WMS field retained for FINatics';
COMMENT ON COLUMN core.LOCATION.LOC_TYPE IS 'KEEP: Existing WMS field retained for FINatics';
COMMENT ON COLUMN core.LOCATION.LOCK_STATUS IS 'KEEP: Inventory/location hold state';
COMMENT ON COLUMN core.LOCATION.VOLUME IS 'KEEP: Existing WMS field retained for FINatics';
COMMENT ON COLUMN core.LOCATION.HEIGHT IS 'KEEP: Existing WMS field retained for FINatics';
COMMENT ON COLUMN core.LOCATION.DEPTH IS 'KEEP: Existing WMS field retained for FINatics';
COMMENT ON COLUMN core.LOCATION.WIDTH IS 'KEEP: Existing WMS field retained for FINatics';
COMMENT ON COLUMN core.LOCATION.WEIGHT IS 'KEEP: Existing WMS field retained for FINatics';
COMMENT ON COLUMN core.LOCATION.DISALLOW_ALLOC IS 'KEEP: Existing WMS field retained for FINatics';
COMMENT ON COLUMN core.LOCATION.COUNT_DSTAMP IS 'KEEP: Audit/operational timestamp';
COMMENT ON COLUMN core.LOCATION.PICK_FACE IS 'KEEP: Existing WMS field retained for FINatics';
COMMENT ON COLUMN core.LOCATION.COUNT_NEEDED IS 'KEEP: Existing WMS field retained for FINatics';
COMMENT ON COLUMN core.LOCATION.AISLE IS 'KEEP: Existing WMS field retained for FINatics';
COMMENT ON COLUMN core.LOCATION.BAY IS 'KEEP: Existing WMS field retained for FINatics';
COMMENT ON COLUMN core.LOCATION.LEVELS IS 'KEEP: Existing WMS field retained for FINatics';
COMMENT ON COLUMN core.LOCATION.POSITION IS 'KEEP: Existing WMS field retained for FINatics';
COMMENT ON COLUMN core.LOCATION.LOCALITY IS 'KEEP: Existing WMS field retained for FINatics';
COMMENT ON COLUMN core.LOCATION.MAX_UNITS_ON_LOC IS 'KEEP: Existing WMS field retained for FINatics';
COMMENT ON COLUMN core.LOCATION.ID IS 'KEEP: Existing WMS field retained for FINatics';
COMMENT ON COLUMN core.LOCATION.DESCRIPTION IS 'ADD: Friendly location/tank description';
COMMENT ON COLUMN core.LOCATION.ACTIVE IS 'ADD: Whether location is operational';
COMMENT ON COLUMN core.LOCATION.LIVESTOCK_ALLOWED IS 'ADD: Whether livestock can be held here';
