CREATE STREAM IF NOT EXISTS {{ .DB }}.sig_live_5s_traffic (
    src_ip  ipv4,
    live_bytes uint64,
    w_start datetime64(3, 'UTC'),
    w_end   datetime64(3, 'UTC')
)
TTL to_datetime(_tp_time) + INTERVAL {{ .Config.retention_hours }} HOUR
SETTINGS logstore_retention_bytes = '{{ .Config.logstore_retention_bytes }}', logstore_retention_ms = '{{ .Config.logstore_retention_ms }}'