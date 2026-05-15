CREATE STREAM IF NOT EXISTS {{ .DB }}.exchange_order
(
    event_ts        uint64,
    TradeDate       date,
    OrderId         string,
    SecurityExchange string,
    SecurityAccount string,
    SecurityId      string,
    Symbol          string,
    Side            string,
    Quantity        float64,
    Price           float64,
    CumQuantity     float64,
    OrdStatus       string,
    StrategyId      string,
    _tp_time        datetime64(6) DEFAULT now64(6)
)
PARTITION BY to_YYYYMM(_tp_time)
TTL to_datetime(_tp_time) + INTERVAL {{ .Config.stream_ttl_hours }} HOUR
SETTINGS index_granularity = 8192, logstore_retention_bytes = '107374182', logstore_retention_ms = '300000';
