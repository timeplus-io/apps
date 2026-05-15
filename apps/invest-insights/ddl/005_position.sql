CREATE MUTABLE STREAM IF NOT EXISTS {{ .DB }}.position
(
    event_ts        uint64,
    TradeDate       date,
    SecurityAccount string,
    SecurityId      string,
    HoldingQty      float64
)
PRIMARY KEY (SecurityAccount, SecurityId)
SETTINGS logstore_retention_bytes = {{ .Config.logstore_retention_bytes }}, logstore_retention_ms = {{ .Config.logstore_retention_ms }};
