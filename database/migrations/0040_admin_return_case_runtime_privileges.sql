-- WMS 0.3.18 - Admin return/claim runtime write privileges
--
-- Migration 0037 established the original Admin control-plane runtime
-- privileges. 0.3.18 now creates and manages RETURN_CASE records directly
-- and persists item-level RETURN_CASE_LINE records.
--
-- Keep this as a forward migration rather than modifying 0037.

BEGIN;

DO $$
DECLARE
    v_app_role name;
BEGIN
    SELECT pg_get_userbyid(nspowner)
      INTO v_app_role
      FROM pg_namespace
     WHERE nspname = 'core';

    IF v_app_role IS NULL THEN
        RAISE EXCEPTION 'CORE_SCHEMA_OWNER_NOT_FOUND';
    END IF;

    EXECUTE format(
        'GRANT SELECT, INSERT, UPDATE ON core.return_case TO %I',
        v_app_role
    );

    EXECUTE format(
        'GRANT SELECT, INSERT ON core.return_case_line TO %I',
        v_app_role
    );
END
$$;

COMMIT;
