CREATE MATERIALIZED VIEW IF NOT EXISTS {{ .DB }}.mv_position
INTO {{ .DB }}.position
AS SELECT
    to_unix_timestamp64_milli(now64(3)) AS event_ts,
    today()                              AS TradeDate,
    concat('a', account_idx::string)     AS SecurityAccount,
    to_string(100000 + security_idx)     AS SecurityId,
    5000::float64 + price_delta * 100   AS HoldingQty
FROM {{ .DB }}.order_random;
