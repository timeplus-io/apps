CREATE VIEW IF NOT EXISTS {{ .DB }}.rate_v AS
WITH cte AS (
    SELECT
        a.SecurityId,
        a.StrategyId,
        a.OrderId,
        extract(a.Symbol, '.*\.(.*)') AS market,
        a.Side,
        a.Quantity,
        a.CumQuantity,
        a.Price,
        a.OrdStatus,
        a.event_ts,
        b.minReportBalance,
        b.minSpread,
        a._tp_time
    FROM {{ .DB }}.exchange_order AS a
    JOIN {{ .DB }}.cfg AS b ON a.SecurityId = b.securityId
)
SELECT
    SecurityId,
    StrategyId,
    window_start,
    part_rate(OrderId, market, Side, Quantity, CumQuantity, Price, OrdStatus, minReportBalance, minSpread) AS rate,
    max(event_ts) AS event_ts,
    now64(6)       AS ts
FROM tumble(cte, 1s)
GROUP BY SecurityId, StrategyId, window_start;
