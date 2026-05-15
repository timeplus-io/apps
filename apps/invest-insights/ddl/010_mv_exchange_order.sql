CREATE MATERIALIZED VIEW IF NOT EXISTS {{ .DB }}.mv_exchange_order
INTO {{ .DB }}.exchange_order
AS SELECT
    to_unix_timestamp64_milli(now64(3)) AS event_ts,
    today()                              AS TradeDate,
    concat('o', order_idx::string)       AS OrderId,
    'US'                                 AS SecurityExchange,
    concat('a', account_idx::string)     AS SecurityAccount,
    to_string(100000 + security_idx)     AS SecurityId,
    concat(to_string(100000 + security_idx), '.US') AS Symbol,
    if(side > 5, '2', '1')              AS Side,
    500::float64 + price_delta * 10     AS Quantity,
    100::float64 + price_delta          AS Price,
    500::float64 - price_delta * 5      AS CumQuantity,
    '7'                                  AS OrdStatus,
    concat('sta', strategy_idx::string) AS StrategyId
FROM {{ .DB }}.order_random;
