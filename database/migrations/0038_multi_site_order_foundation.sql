
-- 0038_multi_site_order_foundation.sql
-- DYNETIC Generic WMS 0.3.18
--
-- Establish:
--   * independent CLIENT and SITE masters;
--   * explicit CLIENT/SITE applicability;
--   * operational CLIENT + SITE scope;
--   * authoritative WMS-generated order identifiers.
--
-- This migration deliberately fails on ambiguous historical site data.
-- It must never silently move operational records to an arbitrary site.

BEGIN;

-- ---------------------------------------------------------------------------
-- 1. SITE master bootstrap and CLIENT/SITE applicability
-- ---------------------------------------------------------------------------

-- Legacy installations may already contain SITE_ID on operational records
-- while core.SITE itself is empty. Recover those masters from existing
-- operational evidence rather than inventing a site such as HQ.
--
-- This is intentionally generic:
--   * no client name is hard-coded;
--   * a SITE_ID is recovered from existing LOCATION/INVENTORY evidence;
--   * conflicting evidence fails visibly;
--   * SITE remains an independent master.

DO $$
DECLARE
    v_site_id varchar(30);
BEGIN
    FOR v_site_id IN
        SELECT DISTINCT x.SITE_ID
          FROM (
                SELECT NULLIF(BTRIM(SITE_ID),'') AS SITE_ID
                  FROM core.LOCATION

                UNION

                SELECT NULLIF(BTRIM(SITE_ID),'') AS SITE_ID
                  FROM core.INVENTORY
          ) x
         WHERE x.SITE_ID IS NOT NULL
           AND NOT EXISTS (
               SELECT 1
                 FROM core.SITE s
                WHERE s.SITE_ID=x.SITE_ID
           )
         ORDER BY x.SITE_ID
    LOOP
        INSERT INTO core.SITE (
            SITE_ID,
            DESCRIPTION,
            SITE_TYPE,
            TIME_ZONE,
            ACTIVE
        )
        VALUES (
            v_site_id,
            v_site_id,
            'FULFILMENT',
            'Europe/London',
            true
        )
        ON CONFLICT (SITE_ID) DO NOTHING;
    END LOOP;
END;
$$;

-- Validate that every operational SITE_ID now has a master.
DO $$
DECLARE
    v_count integer;
BEGIN
    SELECT COUNT(*)
      INTO v_count
      FROM (
            SELECT DISTINCT NULLIF(BTRIM(SITE_ID),'') AS SITE_ID
              FROM core.LOCATION

            UNION

            SELECT DISTINCT NULLIF(BTRIM(SITE_ID),'') AS SITE_ID
              FROM core.INVENTORY
      ) x
      LEFT JOIN core.SITE s
        ON s.SITE_ID=x.SITE_ID
     WHERE x.SITE_ID IS NOT NULL
       AND s.SITE_ID IS NULL;

    IF v_count <> 0 THEN
        RAISE EXCEPTION
          'SITE_MASTER_BOOTSTRAP_FAILED: % operational site identifiers have no SITE master',
          v_count;
    END IF;
END;
$$;

CREATE TABLE IF NOT EXISTS config.CLIENT_SITE (
    CLIENT_ID           varchar(30) NOT NULL REFERENCES core.CLIENT(CLIENT_ID),
    SITE_ID             varchar(30) NOT NULL REFERENCES core.SITE(SITE_ID),
    ACTIVE              boolean NOT NULL DEFAULT true,
    DEFAULT_FULFILMENT  boolean NOT NULL DEFAULT false,
    CREATED_DSTAMP      timestamptz NOT NULL DEFAULT now(),
    LAST_UPDATE_DSTAMP  timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (CLIENT_ID, SITE_ID)
);

COMMENT ON TABLE config.CLIENT_SITE IS
'Operational applicability between independent CLIENT and SITE masters.';

COMMENT ON COLUMN config.CLIENT_SITE.DEFAULT_FULFILMENT IS
'Default fulfilment site for a client when an inbound channel does not explicitly resolve a site.';

-- Recover CLIENT/SITE applicability from existing inventory evidence.
-- A client/site pair is established only where the operational records already
-- explicitly contain both values. This is applicability, not SITE ownership.
INSERT INTO config.CLIENT_SITE (
    CLIENT_ID,
    SITE_ID,
    ACTIVE,
    DEFAULT_FULFILMENT
)
SELECT DISTINCT
    i.CLIENT_ID,
    i.SITE_ID,
    true,
    false
  FROM core.INVENTORY i
  JOIN core.CLIENT c
    ON c.CLIENT_ID=i.CLIENT_ID
   AND c.ACTIVE=true
  JOIN core.SITE s
    ON s.SITE_ID=i.SITE_ID
   AND s.ACTIVE=true
 WHERE i.CLIENT_ID IS NOT NULL
   AND BTRIM(i.CLIENT_ID)<>''
   AND i.SITE_ID IS NOT NULL
   AND BTRIM(i.SITE_ID)<>''
ON CONFLICT (CLIENT_ID,SITE_ID)
DO UPDATE
   SET ACTIVE=true,
       LAST_UPDATE_DSTAMP=now();

-- Preserve the legacy SITE -> CLIENT relationship BEFORE removing CLIENT_ID.
-- Dynamic SQL is required so this migration also remains rerunnable after the
-- legacy column has already been removed.
DO $$
BEGIN
    IF EXISTS (
        SELECT 1
          FROM information_schema.columns
         WHERE table_schema='core'
           AND table_name='site'
           AND column_name='client_id'
    ) THEN
        EXECUTE $sql$
            INSERT INTO config.CLIENT_SITE (
                CLIENT_ID,
                SITE_ID,
                ACTIVE,
                DEFAULT_FULFILMENT
            )
            SELECT
                s.CLIENT_ID,
                s.SITE_ID,
                COALESCE(s.ACTIVE,true),
                false
              FROM core.SITE s
             WHERE s.CLIENT_ID IS NOT NULL
               AND BTRIM(s.CLIENT_ID) <> ''
            ON CONFLICT (CLIENT_ID,SITE_ID)
            DO UPDATE
               SET ACTIVE=EXCLUDED.ACTIVE,
                   LAST_UPDATE_DSTAMP=now()
        $sql$;
    END IF;
END;
$$;

-- If a client has exactly one active applicable site, it is unambiguous and
-- can safely become that client's default fulfilment site.
UPDATE config.CLIENT_SITE cs
   SET DEFAULT_FULFILMENT=true,
       LAST_UPDATE_DSTAMP=now()
 WHERE cs.ACTIVE=true
   AND (
       SELECT COUNT(*)
         FROM config.CLIENT_SITE x
        WHERE x.CLIENT_ID=cs.CLIENT_ID
          AND x.ACTIVE=true
   )=1;

CREATE UNIQUE INDEX IF NOT EXISTS uq_client_site_default_fulfilment
    ON config.CLIENT_SITE (CLIENT_ID)
    WHERE ACTIVE=true
      AND DEFAULT_FULFILMENT=true;

-- Every legacy SITE.CLIENT_ID relationship must have been preserved before
-- SITE ownership is removed.
DO $$
DECLARE
    v_missing integer;
BEGIN
    IF EXISTS (
        SELECT 1
          FROM information_schema.columns
         WHERE table_schema='core'
           AND table_name='site'
           AND column_name='client_id'
    ) THEN
        EXECUTE $sql$
            SELECT COUNT(*)
              FROM core.SITE s
              LEFT JOIN config.CLIENT_SITE cs
                ON cs.CLIENT_ID=s.CLIENT_ID
               AND cs.SITE_ID=s.SITE_ID
             WHERE s.CLIENT_ID IS NOT NULL
               AND BTRIM(s.CLIENT_ID) <> ''
               AND cs.CLIENT_ID IS NULL
        $sql$
        INTO v_missing;

        IF v_missing <> 0 THEN
            RAISE EXCEPTION
              'CLIENT_SITE_MIGRATION_FAILED: % legacy SITE/CLIENT relationships were not preserved',
              v_missing;
        END IF;
    END IF;
END;
$$;

-- SITE now becomes a genuinely independent master.
-- No CASCADE: unexpected external dependencies must fail visibly.
ALTER TABLE core.SITE
    DROP COLUMN IF EXISTS CLIENT_ID;

-- ---------------------------------------------------------------------------
-- 2. LOCATION site scope
-- ---------------------------------------------------------------------------

-- Where LOCATION.SITE_ID is missing, derive it only when inventory at that
-- location points to clients which collectively resolve to exactly one site.
WITH candidates AS (
    SELECT
        l.LOCATION_ID,
        MIN(cs.SITE_ID) AS SITE_ID,
        COUNT(DISTINCT cs.SITE_ID) AS SITE_COUNT
      FROM core.LOCATION l
      JOIN core.INVENTORY i
        ON i.LOCATION_ID=l.LOCATION_ID
      JOIN config.CLIENT_SITE cs
        ON cs.CLIENT_ID=i.CLIENT_ID
       AND cs.ACTIVE=true
     WHERE l.SITE_ID IS NULL
        OR BTRIM(l.SITE_ID)=''
     GROUP BY l.LOCATION_ID
)
UPDATE core.LOCATION l
   SET SITE_ID=c.SITE_ID
  FROM candidates c
 WHERE c.LOCATION_ID=l.LOCATION_ID
   AND c.SITE_COUNT=1
   AND (l.SITE_ID IS NULL OR BTRIM(l.SITE_ID)='');

DO $$
DECLARE
    v_count integer;
BEGIN
    SELECT COUNT(*)
      INTO v_count
      FROM core.LOCATION
     WHERE SITE_ID IS NULL
        OR BTRIM(SITE_ID)='';

    IF v_count <> 0 THEN
        RAISE EXCEPTION
          'SITE_BACKFILL_AMBIGUOUS: % LOCATION rows have no safely derivable SITE_ID',
          v_count;
    END IF;

    SELECT COUNT(*)
      INTO v_count
      FROM core.LOCATION l
      LEFT JOIN core.SITE s
        ON s.SITE_ID=l.SITE_ID
     WHERE s.SITE_ID IS NULL;

    IF v_count <> 0 THEN
        RAISE EXCEPTION
          'SITE_VALIDATION_FAILED: % LOCATION rows reference an unknown SITE',
          v_count;
    END IF;
END;
$$;

ALTER TABLE core.LOCATION
    ALTER COLUMN SITE_ID SET NOT NULL;

ALTER TABLE core.LOCATION
    DROP CONSTRAINT IF EXISTS location_site_id_fkey;

ALTER TABLE core.LOCATION
    ADD CONSTRAINT location_site_id_fkey
    FOREIGN KEY (SITE_ID)
    REFERENCES core.SITE(SITE_ID);

ALTER TABLE core.LOCATION
    DROP CONSTRAINT IF EXISTS uq_location_site_location;

ALTER TABLE core.LOCATION
    ADD CONSTRAINT uq_location_site_location
    UNIQUE (SITE_ID, LOCATION_ID);

-- ---------------------------------------------------------------------------
-- 3. INVENTORY = CLIENT + SITE + SKU + LOCATION
-- ---------------------------------------------------------------------------

-- The physical location is authoritative when it is known.
UPDATE core.INVENTORY i
   SET SITE_ID=l.SITE_ID
  FROM core.LOCATION l
 WHERE i.LOCATION_ID=l.LOCATION_ID
   AND (i.SITE_ID IS NULL OR BTRIM(i.SITE_ID)='');

-- If inventory has no usable location-derived site, use the client's site only
-- when the client has exactly one active applicable site.
WITH single_site AS (
    SELECT
        CLIENT_ID,
        MIN(SITE_ID) AS SITE_ID
      FROM config.CLIENT_SITE
     WHERE ACTIVE=true
     GROUP BY CLIENT_ID
    HAVING COUNT(*)=1
)
UPDATE core.INVENTORY i
   SET SITE_ID=s.SITE_ID
  FROM single_site s
 WHERE s.CLIENT_ID=i.CLIENT_ID
   AND (i.SITE_ID IS NULL OR BTRIM(i.SITE_ID)='');

DO $$
DECLARE
    v_count integer;
BEGIN
    SELECT COUNT(*)
      INTO v_count
      FROM core.INVENTORY
     WHERE SITE_ID IS NULL
        OR BTRIM(SITE_ID)='';

    IF v_count <> 0 THEN
        RAISE EXCEPTION
          'SITE_BACKFILL_AMBIGUOUS: % INVENTORY rows have no safely derivable SITE_ID',
          v_count;
    END IF;

    SELECT COUNT(*)
      INTO v_count
      FROM core.INVENTORY i
      LEFT JOIN config.CLIENT_SITE cs
        ON cs.CLIENT_ID=i.CLIENT_ID
       AND cs.SITE_ID=i.SITE_ID
       AND cs.ACTIVE=true
     WHERE cs.CLIENT_ID IS NULL;

    IF v_count <> 0 THEN
        RAISE EXCEPTION
          'CLIENT_SITE_VALIDATION_FAILED: % INVENTORY rows fall outside active CLIENT/SITE applicability',
          v_count;
    END IF;

    SELECT COUNT(*)
      INTO v_count
      FROM core.INVENTORY i
      JOIN core.LOCATION l
        ON l.LOCATION_ID=i.LOCATION_ID
     WHERE l.SITE_ID<>i.SITE_ID;

    IF v_count <> 0 THEN
        RAISE EXCEPTION
          'SITE_LOCATION_MISMATCH: % INVENTORY rows disagree with LOCATION.SITE_ID',
          v_count;
    END IF;
END;
$$;

ALTER TABLE core.INVENTORY
    ALTER COLUMN SITE_ID SET NOT NULL;

ALTER TABLE core.INVENTORY
    DROP CONSTRAINT IF EXISTS inventory_site_id_fkey;

ALTER TABLE core.INVENTORY
    ADD CONSTRAINT inventory_site_id_fkey
    FOREIGN KEY (SITE_ID)
    REFERENCES core.SITE(SITE_ID);

ALTER TABLE core.INVENTORY
    DROP CONSTRAINT IF EXISTS inventory_site_location_fkey;

ALTER TABLE core.INVENTORY
    ADD CONSTRAINT inventory_site_location_fkey
    FOREIGN KEY (SITE_ID, LOCATION_ID)
    REFERENCES core.LOCATION(SITE_ID, LOCATION_ID);

-- ---------------------------------------------------------------------------
-- 4. ORDER operational site
-- ---------------------------------------------------------------------------

ALTER TABLE core.ORDER_HEADER
    ADD COLUMN IF NOT EXISTS SITE_ID varchar(30);

-- Existing FROM_SITE_ID is the strongest existing order-level evidence.
UPDATE core.ORDER_HEADER
   SET SITE_ID=FROM_SITE_ID
 WHERE (SITE_ID IS NULL OR BTRIM(SITE_ID)='')
   AND FROM_SITE_ID IS NOT NULL
   AND BTRIM(FROM_SITE_ID)<>'';

-- Otherwise derive only when the client has one active applicable site.
WITH single_site AS (
    SELECT
        CLIENT_ID,
        MIN(SITE_ID) AS SITE_ID
      FROM config.CLIENT_SITE
     WHERE ACTIVE=true
     GROUP BY CLIENT_ID
    HAVING COUNT(*)=1
)
UPDATE core.ORDER_HEADER oh
   SET SITE_ID=s.SITE_ID
  FROM single_site s
 WHERE s.CLIENT_ID=oh.CLIENT_ID
   AND (oh.SITE_ID IS NULL OR BTRIM(oh.SITE_ID)='');

DO $$
DECLARE
    v_count integer;
BEGIN
    SELECT COUNT(*)
      INTO v_count
      FROM core.ORDER_HEADER
     WHERE SITE_ID IS NULL
        OR BTRIM(SITE_ID)='';

    IF v_count <> 0 THEN
        RAISE EXCEPTION
          'SITE_BACKFILL_AMBIGUOUS: % ORDER_HEADER rows have no safely derivable SITE_ID',
          v_count;
    END IF;

    SELECT COUNT(*)
      INTO v_count
      FROM core.ORDER_HEADER oh
      LEFT JOIN config.CLIENT_SITE cs
        ON cs.CLIENT_ID=oh.CLIENT_ID
       AND cs.SITE_ID=oh.SITE_ID
       AND cs.ACTIVE=true
     WHERE cs.CLIENT_ID IS NULL;

    IF v_count <> 0 THEN
        RAISE EXCEPTION
          'CLIENT_SITE_VALIDATION_FAILED: % ORDER_HEADER rows fall outside active CLIENT/SITE applicability',
          v_count;
    END IF;

    SELECT COUNT(*)
      INTO v_count
      FROM core.ORDER_HEADER oh
      LEFT JOIN core.SITE s
        ON s.SITE_ID=oh.FROM_SITE_ID
     WHERE oh.FROM_SITE_ID IS NOT NULL
       AND BTRIM(oh.FROM_SITE_ID)<>''
       AND s.SITE_ID IS NULL;

    IF v_count <> 0 THEN
        RAISE EXCEPTION
          'SITE_VALIDATION_FAILED: % ORDER_HEADER FROM_SITE_ID values reference unknown sites',
          v_count;
    END IF;

    SELECT COUNT(*)
      INTO v_count
      FROM core.ORDER_HEADER oh
      LEFT JOIN core.SITE s
        ON s.SITE_ID=oh.TO_SITE_ID
     WHERE oh.TO_SITE_ID IS NOT NULL
       AND BTRIM(oh.TO_SITE_ID)<>''
       AND s.SITE_ID IS NULL;

    IF v_count <> 0 THEN
        RAISE EXCEPTION
          'SITE_VALIDATION_FAILED: % ORDER_HEADER TO_SITE_ID values reference unknown sites',
          v_count;
    END IF;
END;
$$;

ALTER TABLE core.ORDER_HEADER
    ALTER COLUMN SITE_ID SET NOT NULL;

ALTER TABLE core.ORDER_HEADER
    DROP CONSTRAINT IF EXISTS order_header_site_id_fkey;

ALTER TABLE core.ORDER_HEADER
    ADD CONSTRAINT order_header_site_id_fkey
    FOREIGN KEY (SITE_ID)
    REFERENCES core.SITE(SITE_ID);

ALTER TABLE core.ORDER_HEADER
    DROP CONSTRAINT IF EXISTS order_header_from_site_id_fkey;

ALTER TABLE core.ORDER_HEADER
    ADD CONSTRAINT order_header_from_site_id_fkey
    FOREIGN KEY (FROM_SITE_ID)
    REFERENCES core.SITE(SITE_ID);

ALTER TABLE core.ORDER_HEADER
    DROP CONSTRAINT IF EXISTS order_header_to_site_id_fkey;

ALTER TABLE core.ORDER_HEADER
    ADD CONSTRAINT order_header_to_site_id_fkey
    FOREIGN KEY (TO_SITE_ID)
    REFERENCES core.SITE(SITE_ID);

COMMENT ON COLUMN core.ORDER_HEADER.SITE_ID IS
'Authoritative operational/fulfilment site for the order.';

-- ---------------------------------------------------------------------------
-- 5. ORDER interface site
-- ---------------------------------------------------------------------------

ALTER TABLE interface.ORDER_HEADER_IF
    ADD COLUMN IF NOT EXISTS SITE_ID varchar(30);

-- Existing interface rows can be resolved only when their client has one
-- active applicable site. Ambiguous multi-site rows must be corrected by data
-- migration rather than guessed.
WITH single_site AS (
    SELECT
        CLIENT_ID,
        MIN(SITE_ID) AS SITE_ID
      FROM config.CLIENT_SITE
     WHERE ACTIVE=true
     GROUP BY CLIENT_ID
    HAVING COUNT(*)=1
)
UPDATE interface.ORDER_HEADER_IF h
   SET SITE_ID=s.SITE_ID
  FROM single_site s
 WHERE s.CLIENT_ID=h.CLIENT_ID
   AND (h.SITE_ID IS NULL OR BTRIM(h.SITE_ID)='');

DO $$
DECLARE
    v_count integer;
BEGIN
    SELECT COUNT(*)
      INTO v_count
      FROM interface.ORDER_HEADER_IF
     WHERE SITE_ID IS NULL
        OR BTRIM(SITE_ID)='';

    IF v_count <> 0 THEN
        RAISE EXCEPTION
          'SITE_BACKFILL_AMBIGUOUS: % ORDER_HEADER_IF rows have no safely derivable SITE_ID',
          v_count;
    END IF;

    SELECT COUNT(*)
      INTO v_count
      FROM interface.ORDER_HEADER_IF h
      LEFT JOIN config.CLIENT_SITE cs
        ON cs.CLIENT_ID=h.CLIENT_ID
       AND cs.SITE_ID=h.SITE_ID
       AND cs.ACTIVE=true
     WHERE cs.CLIENT_ID IS NULL;

    IF v_count <> 0 THEN
        RAISE EXCEPTION
          'CLIENT_SITE_VALIDATION_FAILED: % ORDER_HEADER_IF rows fall outside active CLIENT/SITE applicability',
          v_count;
    END IF;
END;
$$;

ALTER TABLE interface.ORDER_HEADER_IF
    ALTER COLUMN SITE_ID SET NOT NULL;

ALTER TABLE interface.ORDER_HEADER_IF
    DROP CONSTRAINT IF EXISTS order_header_if_site_id_fkey;

ALTER TABLE interface.ORDER_HEADER_IF
    ADD CONSTRAINT order_header_if_site_id_fkey
    FOREIGN KEY (SITE_ID)
    REFERENCES core.SITE(SITE_ID);

COMMENT ON COLUMN interface.ORDER_HEADER_IF.SITE_ID IS
'Target operational/fulfilment site for Generic WMS order ingestion.';

-- ---------------------------------------------------------------------------
-- 6. PRE-ADVICE operational site
-- ---------------------------------------------------------------------------

-- PRE_ADVICE_HEADER already carries CLIENT_ID + SITE_ID.
-- Only resolve missing values where the client has exactly one active site.
WITH single_site AS (
    SELECT
        CLIENT_ID,
        MIN(SITE_ID) AS SITE_ID
      FROM config.CLIENT_SITE
     WHERE ACTIVE=true
     GROUP BY CLIENT_ID
    HAVING COUNT(*)=1
)
UPDATE core.PRE_ADVICE_HEADER p
   SET SITE_ID=s.SITE_ID
  FROM single_site s
 WHERE s.CLIENT_ID=p.CLIENT_ID
   AND (p.SITE_ID IS NULL OR BTRIM(p.SITE_ID)='');

DO $$
DECLARE
    v_count integer;
BEGIN
    SELECT COUNT(*)
      INTO v_count
      FROM core.PRE_ADVICE_HEADER
     WHERE SITE_ID IS NULL
        OR BTRIM(SITE_ID)='';

    IF v_count <> 0 THEN
        RAISE EXCEPTION
          'SITE_BACKFILL_AMBIGUOUS: % PRE_ADVICE_HEADER rows have no safely derivable SITE_ID',
          v_count;
    END IF;

    SELECT COUNT(*)
      INTO v_count
      FROM core.PRE_ADVICE_HEADER p
      LEFT JOIN config.CLIENT_SITE cs
        ON cs.CLIENT_ID=p.CLIENT_ID
       AND cs.SITE_ID=p.SITE_ID
       AND cs.ACTIVE=true
     WHERE cs.CLIENT_ID IS NULL;

    IF v_count <> 0 THEN
        RAISE EXCEPTION
          'CLIENT_SITE_VALIDATION_FAILED: % PRE_ADVICE_HEADER rows fall outside active CLIENT/SITE applicability',
          v_count;
    END IF;
END;
$$;

ALTER TABLE core.PRE_ADVICE_HEADER
    ALTER COLUMN SITE_ID SET NOT NULL;

-- ---------------------------------------------------------------------------
-- 7. Authoritative order numbering
-- ---------------------------------------------------------------------------

ALTER TABLE core.CLIENT
    ADD COLUMN IF NOT EXISTS ORDER_PREFIX varchar(4);

UPDATE core.CLIENT
   SET ORDER_PREFIX=LEFT(
       REGEXP_REPLACE(UPPER(CLIENT_ID),'[^A-Z0-9]','','g'),
       4
   )
 WHERE ORDER_PREFIX IS NULL
    OR BTRIM(ORDER_PREFIX)='';

DO $$
DECLARE
    v_count integer;
BEGIN
    SELECT COUNT(*)
      INTO v_count
      FROM core.CLIENT
     WHERE ORDER_PREFIX IS NULL
        OR ORDER_PREFIX !~ '^[A-Z0-9]{1,4}$';

    IF v_count <> 0 THEN
        RAISE EXCEPTION
          'ORDER_PREFIX_INVALID: % clients do not have a valid 1-4 character order prefix',
          v_count;
    END IF;

    SELECT COUNT(*)
      INTO v_count
      FROM (
            SELECT ORDER_PREFIX
              FROM core.CLIENT
             GROUP BY ORDER_PREFIX
            HAVING COUNT(*)>1
      ) x;

    IF v_count <> 0 THEN
        RAISE EXCEPTION
          'ORDER_PREFIX_COLLISION: % duplicate order-prefix namespaces exist; configure unique prefixes before continuing',
          v_count;
    END IF;
END;
$$;

ALTER TABLE core.CLIENT
    ALTER COLUMN ORDER_PREFIX SET NOT NULL;

ALTER TABLE core.CLIENT
    DROP CONSTRAINT IF EXISTS client_order_prefix_format_ck;

ALTER TABLE core.CLIENT
    ADD CONSTRAINT client_order_prefix_format_ck
    CHECK (ORDER_PREFIX ~ '^[A-Z0-9]{1,4}$');

ALTER TABLE core.CLIENT
    DROP CONSTRAINT IF EXISTS client_order_prefix_unique;

ALTER TABLE core.CLIENT
    ADD CONSTRAINT client_order_prefix_unique
    UNIQUE (ORDER_PREFIX);

CREATE TABLE IF NOT EXISTS core.ORDER_NUMBER_SEQUENCE (
    CLIENT_ID       varchar(30) PRIMARY KEY REFERENCES core.CLIENT(CLIENT_ID),
    LAST_NUMBER     bigint NOT NULL DEFAULT 0,
    LAST_DSTAMP     timestamptz NOT NULL DEFAULT now()
);

-- ORDER_PREFIX is constrained to alphanumeric characters, so it can be used
-- directly in the regular expression without regex escaping.
INSERT INTO core.ORDER_NUMBER_SEQUENCE (
    CLIENT_ID,
    LAST_NUMBER,
    LAST_DSTAMP
)
SELECT
    c.CLIENT_ID,
    COALESCE(
        MAX(
            CASE
                WHEN oh.ORDER_ID ~ ('^' || c.ORDER_PREFIX || '-[0-9]{10}$')
                THEN substring(oh.ORDER_ID from '([0-9]{10})$')::bigint
                ELSE NULL
            END
        ),
        0
    ),
    now()
FROM core.CLIENT c
LEFT JOIN core.ORDER_HEADER oh
       ON oh.CLIENT_ID=c.CLIENT_ID
GROUP BY c.CLIENT_ID
ON CONFLICT (CLIENT_ID)
DO UPDATE
   SET LAST_NUMBER=GREATEST(
           core.ORDER_NUMBER_SEQUENCE.LAST_NUMBER,
           EXCLUDED.LAST_NUMBER
       ),
       LAST_DSTAMP=now();

CREATE OR REPLACE FUNCTION core.NEXT_ORDER_ID(
    p_client_id varchar
)
RETURNS varchar
LANGUAGE plpgsql
AS $$
DECLARE
    v_prefix varchar(4);
    v_number bigint;
    v_order_id varchar(20);
BEGIN
    SELECT ORDER_PREFIX
      INTO v_prefix
      FROM core.CLIENT
     WHERE CLIENT_ID=p_client_id
       AND ACTIVE=true;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'CLIENT_NOT_FOUND: %', p_client_id;
    END IF;

    LOOP
        INSERT INTO core.ORDER_NUMBER_SEQUENCE (
            CLIENT_ID,
            LAST_NUMBER,
            LAST_DSTAMP
        )
        VALUES (
            p_client_id,
            1,
            now()
        )
        ON CONFLICT (CLIENT_ID)
        DO UPDATE
           SET LAST_NUMBER=core.ORDER_NUMBER_SEQUENCE.LAST_NUMBER + 1,
               LAST_DSTAMP=now()
        RETURNING LAST_NUMBER
             INTO v_number;

        v_order_id :=
            v_prefix || '-' || LPAD(v_number::text,10,'0');

        EXIT WHEN NOT EXISTS (
            SELECT 1
              FROM core.ORDER_HEADER
             WHERE CLIENT_ID=p_client_id
               AND ORDER_ID=v_order_id
        );
    END LOOP;

    RETURN v_order_id;
END;
$$;

COMMENT ON FUNCTION core.NEXT_ORDER_ID(varchar) IS
'Allocates the next authoritative collision-safe human-readable order identifier for a client.';

COMMIT;
