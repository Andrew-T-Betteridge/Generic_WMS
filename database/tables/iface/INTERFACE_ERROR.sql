CREATE TABLE IF NOT EXISTS iface.interface_error (
    error_id          bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    client_id         varchar(30) REFERENCES core.client(client_id),
    interface_name    varchar(50) NOT NULL,
    source_system     varchar(50),
    source_reference  varchar(100),
    record_reference  varchar(100),
    error_code        varchar(50),
    error_message     text NOT NULL,
    error_detail      jsonb,
    created_dstamp    timestamptz NOT NULL DEFAULT now(),
    resolved          boolean NOT NULL DEFAULT false,
    resolved_dstamp   timestamptz,
    resolved_by       varchar(100)
);
