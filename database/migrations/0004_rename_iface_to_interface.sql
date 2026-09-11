DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM pg_namespace WHERE nspname = 'iface')
       AND NOT EXISTS (SELECT 1 FROM pg_namespace WHERE nspname = 'interface') THEN
        EXECUTE 'ALTER SCHEMA iface RENAME TO interface';
    ELSIF NOT EXISTS (SELECT 1 FROM pg_namespace WHERE nspname = 'interface') THEN
        EXECUTE 'CREATE SCHEMA interface';
    END IF;
END $$;
