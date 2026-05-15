CREATE MATERIALIZED VIEW IF NOT EXISTS {{ .DB }}.mv_execution
INTO {{ .DB }}.execution
AS SELECT
    to_unix_timestamp64_milli(now64(3))     AS event_ts,
    concat('e', order_idx::string)           AS OrderId,
    today()                                  AS TradeDate,
    concat('a', account_idx::string)         AS SecurityAccount,
    to_string(100000 + security_idx)         AS SecurityId,
    if(side > 5, '2', '1')                  AS EntrustDirection,
    500::float64 + price_delta * 10         AS LastQty,
    100::float64 + price_delta              AS LastPx,
    0.0001 * (500 + price_delta * 10) * (100 + price_delta) AS Fee,
    concat('sta', strategy_idx::string)     AS StrategyId
FROM {{ .DB }}.order_random;
