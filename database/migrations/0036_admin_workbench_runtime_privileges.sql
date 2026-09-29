BEGIN;

-- Workbench views introduced by migration 0032 are created by the privileged
-- migration role. Grant their runtime read access to the Generic WMS
-- application role, derived from the owner of the core schema.
--
-- Do not hard-code a deployment-specific role such as dynetic_app.

DO $$
DECLARE
    v_app_role name;
BEGIN
    SELECT pg_get_userbyid(nspowner)
      INTO v_app_role
      FROM pg_namespace
     WHERE nspname='core';

    IF v_app_role IS NULL THEN
        RAISE EXCEPTION 'CORE_SCHEMA_OWNER_NOT_FOUND';
    END IF;

    IF to_regclass('core.admin_order_control_workbench') IS NULL
       OR to_regclass('core.admin_payment_workbench') IS NULL
       OR to_regclass('core.admin_exception_workbench') IS NULL THEN
        RAISE EXCEPTION 'ADMIN_WORKBENCH_VIEW_NOT_FOUND';
    END IF;

    EXECUTE format(
        'GRANT SELECT ON core.admin_order_control_workbench, core.admin_payment_workbench, core.admin_exception_workbench TO %I',
        v_app_role
    );
END
$$;

COMMIT;
