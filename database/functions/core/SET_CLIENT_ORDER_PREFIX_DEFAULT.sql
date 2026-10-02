
-- ---------------------------------------------------------------------------
-- CLIENT order-prefix default
--
-- 0.3.18 introduced ORDER_PREFIX as a required, unique client attribute.
-- Existing clients were backfilled, but clients created after the migration
-- had no database-level implementation of the documented default.
-- Preserve explicit prefixes; derive a missing prefix from CLIENT_ID.
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION core.SET_CLIENT_ORDER_PREFIX_DEFAULT()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    IF NEW.ORDER_PREFIX IS NULL
       OR BTRIM(NEW.ORDER_PREFIX) = '' THEN
        NEW.ORDER_PREFIX := LEFT(
            REGEXP_REPLACE(
                UPPER(NEW.CLIENT_ID),
                '[^A-Z0-9]',
                '',
                'g'
            ),
            4
        );
    ELSE
        NEW.ORDER_PREFIX := UPPER(BTRIM(NEW.ORDER_PREFIX));
    END IF;

    IF NEW.ORDER_PREFIX IS NULL
       OR NEW.ORDER_PREFIX !~ '^[A-Z0-9]{1,4}$' THEN
        RAISE EXCEPTION
          'INVALID_ORDER_PREFIX: client % requires a 1-4 character alphanumeric order prefix',
          NEW.CLIENT_ID;
    END IF;

    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_client_order_prefix_default
    ON core.CLIENT;

CREATE TRIGGER trg_client_order_prefix_default
BEFORE INSERT OR UPDATE OF CLIENT_ID, ORDER_PREFIX
ON core.CLIENT
FOR EACH ROW
EXECUTE FUNCTION core.SET_CLIENT_ORDER_PREFIX_DEFAULT();

COMMENT ON FUNCTION core.SET_CLIENT_ORDER_PREFIX_DEFAULT() IS
'Derives a missing client order prefix from CLIENT_ID while preserving explicit independently configurable prefixes.';
