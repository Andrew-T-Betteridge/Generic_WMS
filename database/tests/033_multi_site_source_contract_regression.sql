
-- 033_multi_site_source_contract_regression.sql
-- DYNETIC Generic WMS 0.3.18 live operational-scope contract.

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
          'FAIL: SITE is not an independent master';
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
          'FAIL: client has multiple active default fulfilment sites';
    END IF;

    SELECT COUNT(*)
      INTO v_count
      FROM core.ORDER_HEADER oh
      LEFT JOIN config.CLIENT_SITE cs
        ON cs.CLIENT_ID=oh.CLIENT_ID
       AND cs.SITE_ID=oh.SITE_ID
       AND cs.ACTIVE=true
     WHERE oh.SITE_ID IS NULL
        OR cs.CLIENT_ID IS NULL;

    IF v_count<>0 THEN
        RAISE EXCEPTION
          'FAIL: ORDER_HEADER contains invalid CLIENT/SITE applicability';
    END IF;

    SELECT COUNT(*)
      INTO v_count
      FROM core.INVENTORY i
      LEFT JOIN config.CLIENT_SITE cs
        ON cs.CLIENT_ID=i.CLIENT_ID
       AND cs.SITE_ID=i.SITE_ID
       AND cs.ACTIVE=true
     WHERE i.SITE_ID IS NULL
        OR cs.CLIENT_ID IS NULL;

    IF v_count<>0 THEN
        RAISE EXCEPTION
          'FAIL: INVENTORY contains invalid CLIENT/SITE applicability';
    END IF;

    SELECT COUNT(*)
      INTO v_count
      FROM core.INVENTORY i
      JOIN core.LOCATION l
        ON l.LOCATION_ID=i.LOCATION_ID
     WHERE i.SITE_ID<>l.SITE_ID;

    IF v_count<>0 THEN
        RAISE EXCEPTION
          'FAIL: INVENTORY and LOCATION disagree on SITE_ID';
    END IF;

    SELECT COUNT(*)
      INTO v_count
      FROM interface.ORDER_HEADER_IF h
      LEFT JOIN config.CLIENT_SITE cs
        ON cs.CLIENT_ID=h.CLIENT_ID
       AND cs.SITE_ID=h.SITE_ID
       AND cs.ACTIVE=true
     WHERE h.SITE_ID IS NULL
        OR cs.CLIENT_ID IS NULL;

    IF v_count<>0 THEN
        RAISE EXCEPTION
          'FAIL: ORDER_HEADER_IF contains invalid CLIENT/SITE applicability';
    END IF;

    SELECT COUNT(*)
      INTO v_count
      FROM core.PRE_ADVICE_HEADER p
      LEFT JOIN config.CLIENT_SITE cs
        ON cs.CLIENT_ID=p.CLIENT_ID
       AND cs.SITE_ID=p.SITE_ID
       AND cs.ACTIVE=true
     WHERE p.SITE_ID IS NULL
        OR cs.CLIENT_ID IS NULL;

    IF v_count<>0 THEN
        RAISE EXCEPTION
          'FAIL: PRE_ADVICE_HEADER contains invalid CLIENT/SITE applicability';
    END IF;

    RAISE NOTICE
      'PASS: 0.3.18 multi-site runtime contract validated';
END;
$$;
