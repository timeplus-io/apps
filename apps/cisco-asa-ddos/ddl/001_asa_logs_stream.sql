CREATE STREAM IF NOT EXISTS {{ .DB }}.asa_logs_stream (
    message string
)
TTL to_datetime(_tp_time) + INTERVAL {{ .Config.retention_hours }} HOUR
SETTINGS logstore_retention_bytes = '{{ .Config.logstore_retention_bytes }}', logstore_retention_ms = '{{ .Config.logstore_retention_ms }}'
