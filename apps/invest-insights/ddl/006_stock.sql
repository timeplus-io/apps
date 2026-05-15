CREATE MUTABLE STREAM IF NOT EXISTS {{ .DB }}.stock
(
    event_ts   uint64,
    SecurityID string,
    Symbol     string,
    PreClosePx float64,
    LastPx     float64,
    OpenPx     float64,
    ClosePx    float64,
    HighPx     float64,
    LowPx      float64
)
PRIMARY KEY SecurityID
SETTINGS logstore_retention_bytes = {{ .Config.logstore_retention_bytes }}, logstore_retention_ms = {{ .Config.logstore_retention_ms }};
