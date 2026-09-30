
-- 034_admin_operational_backbone_regression.sql
-- DYNETIC Generic WMS 0.3.18 operational backbone invariants.

DO $$
DECLARE
    v_count integer;
BEGIN
    IF EXISTS (
        SELECT 1
          FROM information_schema.columns
         WHERE table_schema='core'
           AND table_name='site'
           AND column_name='client_id'
    ) THEN
        RAISE EXCEPTION
          'FAIL: core.SITE must remain an independent master';
    END IF;

    IF to_regclass('config.client_site') IS NULL THEN
        RAISE EXCEPTION
          'FAIL: config.CLIENT_SITE missing';
    END IF;

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

    IF v_count<>0 THEN
        RAISE EXCEPTION
          'FAIL: operational SITE_ID exists without SITE master';
    END IF;

    SELECT COUNT(*)
      INTO v_count
      FROM (
            SELECT ORDER_PREFIX
              FROM core.CLIENT
             WHERE ORDER_PREFIX IS NOT NULL
             GROUP BY ORDER_PREFIX
            HAVING COUNT(*)>1
      ) x;

    IF v_count<>0 THEN
        RAISE EXCEPTION
          'FAIL: duplicate client order prefixes';
    END IF;

    SELECT COUNT(*)
      INTO v_count
      FROM (
            SELECT CLIENT_ID
              FROM config.CLIENT_SITE
             WHERE ACTIVE=true
               AND DEFAULT_FULFILMENT=true
             GROUP BY CLIENT_ID
            HAVING COUNT(*)>1
      ) x;

    IF v_count<>0 THEN
        RAISE EXCEPTION
          'FAIL: multiple default fulfilment sites for a client';
    END IF;

    SELECT COUNT(*)
      INTO v_count
      FROM core.ORDER_HEADER oh
      LEFT JOIN config.CLIENT_SITE cs
        ON cs.CLIENT_ID=oh.CLIENT_ID
       AND cs.SITE_ID=oh.SITE_ID
       AND cs.ACTIVE=true
     WHERE cs.CLIENT_ID IS NULL;

    IF v_count<>0 THEN
        RAISE EXCEPTION
          'FAIL: order outside valid client/site applicability';
    END IF;

    SELECT COUNT(*)
      INTO v_count
      FROM core.INVENTORY i
      LEFT JOIN config.CLIENT_SITE cs
        ON cs.CLIENT_ID=i.CLIENT_ID
       AND cs.SITE_ID=i.SITE_ID
       AND cs.ACTIVE=true
     WHERE cs.CLIENT_ID IS NULL;

    IF v_count<>0 THEN
        RAISE EXCEPTION
          'FAIL: inventory outside valid client/site applicability';
    END IF;

    -- Every generated-style order ID must agree with its client's namespace.
    SELECT COUNT(*)
      INTO v_count
      FROM core.ORDER_HEADER oh
      JOIN core.CLIENT c
        ON c.CLIENT_ID=oh.CLIENT_ID
     WHERE oh.ORDER_ID ~ '^[A-Z0-9]{1,4}-[0-9]{10}$'
       AND oh.ORDER_ID !~ ('^' || c.ORDER_PREFIX || '-[0-9]{10}$');

    IF v_count<>0 THEN
        RAISE EXCEPTION
          'FAIL: generated order ID outside client namespace';
    END IF;

    RAISE NOTICE
      'PASS: 0.3.18 Admin operational backbone invariants';
END;
$$;
