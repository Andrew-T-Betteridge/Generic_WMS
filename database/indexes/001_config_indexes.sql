CREATE INDEX IF NOT EXISTS ix_carrier_selection_rule_client_priority
ON config.carrier_selection_rule (client_id, active, priority);

CREATE INDEX IF NOT EXISTS ix_merge_rule_client_priority
ON config.merge_rule (client_id, active, priority);

CREATE INDEX IF NOT EXISTS ix_interface_error_open
ON iface.interface_error (interface_name, resolved, created_dstamp);

CREATE INDEX IF NOT EXISTS ix_processing_log_process
ON audit.processing_log (process_name, created_dstamp);
