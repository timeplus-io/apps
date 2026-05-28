CREATE STREAM IF NOT EXISTS {{ .DB }}.ocsf_events (
  raw       string,
  class_uid uint32
)
TTL to_datetime(_tp_time) + INTERVAL {{ .Config.retention_hours }} HOUR;
