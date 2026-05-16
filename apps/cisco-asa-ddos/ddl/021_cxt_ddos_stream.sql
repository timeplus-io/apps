CREATE STREAM IF NOT EXISTS {{ .DB }}.cxt_ddos_stream (
    src_ip              ipv4,
    live_bytes          uint64,
    overall_baseline    float64,
    hourly_baseline     float64,
    overall_spike_ratio float64,
    hourly_spike_ratio  float64
)
TTL to_datetime(_tp_time) + INTERVAL {{ .Config.retention_hours }} HOUR
SETTINGS logstore_retention_bytes = '{{ .Config.logstore_retention_bytes }}', logstore_retention_ms = '{{ .Config.logstore_retention_ms }}'