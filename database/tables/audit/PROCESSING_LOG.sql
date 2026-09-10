CREATE TABLE IF NOT EXISTS audit.processing_log (
    log_id          bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    client_id       varchar(30) REFERENCES core.client(client_id),
    process_name    varchar(80) NOT NULL,
    process_run_id  uuid,
    entity_type     varchar(50),
    entity_id       varchar(100),
    status          varchar(30),
    message         text,
    detail          jsonb,
    created_dstamp  timestamptz NOT NULL DEFAULT now(),
    created_by      varchar(100)
);
