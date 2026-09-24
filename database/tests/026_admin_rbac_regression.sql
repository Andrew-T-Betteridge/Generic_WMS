\set ON_ERROR_STOP on

BEGIN;

DO $$
DECLARE
    v_permission_count integer;
    v_owner_count integer;
    v_user_id uuid;
    v_viewer_can_read boolean;
    v_viewer_can_update boolean;
BEGIN
    SELECT count(*) INTO v_permission_count
    FROM config.ADMIN_PERMISSION;

    IF v_permission_count < 25 THEN
        RAISE EXCEPTION 'RBAC regression: expected seeded permissions, got %', v_permission_count;
    END IF;

    SELECT count(*) INTO v_owner_count
    FROM config.ADMIN_ROLE_PERMISSION rp
    WHERE rp.CLIENT_ID='FINATICS'
      AND rp.ROLE_CODE='OWNER';

    IF v_owner_count <> v_permission_count THEN
        RAISE EXCEPTION 'RBAC regression: OWNER does not contain every permission';
    END IF;

    INSERT INTO config.ADMIN_USER
        (CLIENT_ID,EMAIL,DISPLAY_NAME,ACTIVE,CREATED_BY)
    VALUES
        ('FINATICS','rbac-regression@finatics.invalid','RBAC Regression',TRUE,'TEST')
    RETURNING ADMIN_USER_ID INTO v_user_id;

    INSERT INTO config.ADMIN_USER_ROLE
        (CLIENT_ID,ADMIN_USER_ID,ROLE_CODE)
    VALUES
        ('FINATICS',v_user_id,'VIEWER');

    SELECT EXISTS (
        SELECT 1
        FROM config.ADMIN_USER_ROLE ur
        JOIN config.ADMIN_ROLE_PERMISSION rp
          ON rp.CLIENT_ID=ur.CLIENT_ID
         AND rp.ROLE_CODE=ur.ROLE_CODE
        WHERE ur.CLIENT_ID='FINATICS'
          AND ur.ADMIN_USER_ID=v_user_id
          AND rp.PERMISSION_CODE='product.read'
    ) INTO v_viewer_can_read;

    SELECT EXISTS (
        SELECT 1
        FROM config.ADMIN_USER_ROLE ur
        JOIN config.ADMIN_ROLE_PERMISSION rp
          ON rp.CLIENT_ID=ur.CLIENT_ID
         AND rp.ROLE_CODE=ur.ROLE_CODE
        WHERE ur.CLIENT_ID='FINATICS'
          AND ur.ADMIN_USER_ID=v_user_id
          AND rp.PERMISSION_CODE='product.update'
    ) INTO v_viewer_can_update;

    IF NOT v_viewer_can_read THEN
        RAISE EXCEPTION 'RBAC regression: VIEWER should have product.read';
    END IF;

    IF v_viewer_can_update THEN
        RAISE EXCEPTION 'RBAC regression: VIEWER must not have product.update';
    END IF;

    INSERT INTO audit.AUDIT_EVENT
        (CLIENT_ID,ENTITY_TYPE,ENTITY_ID,ACTION,CHANGED_BY,BEFORE_DATA,AFTER_DATA)
    VALUES
        ('FINATICS','ADMIN_USER',v_user_id::text,'TEST','RBAC_TEST',
         '{"active":false}'::jsonb,'{"active":true}'::jsonb);

    IF NOT EXISTS (
        SELECT 1
        FROM audit.AUDIT_EVENT
        WHERE CLIENT_ID='FINATICS'
          AND ENTITY_TYPE='ADMIN_USER'
          AND ENTITY_ID=v_user_id::text
          AND ACTION='TEST'
    ) THEN
        RAISE EXCEPTION 'RBAC regression: audit event was not written';
    END IF;
END
$$;

ROLLBACK;

\echo 'Admin RBAC regression passed.'
