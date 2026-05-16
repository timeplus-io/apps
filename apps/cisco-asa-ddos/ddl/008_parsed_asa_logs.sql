CREATE STREAM IF NOT EXISTS {{ .DB }}.parsed_asa_logs
(
    ingestion_time  datetime64(3),
    log_timestamp   string,
    device_name     string,
    severity        nullable(int8),
    message_id      string,
    asa_message     string
)
TTL to_datetime(_tp_time) + INTERVAL {{ .Config.retention_hours }} HOUR
SETTINGS logstore_retention_bytes = '{{ .Config.logstore_retention_bytes }}', logstore_retention_ms = '{{ .Config.logstore_retention_ms }}'