CREATE MATERIALIZED VIEW IF NOT EXISTS {{ .DB }}.mv_coinbase_1s
INTO {{ .DB }}.coinbase_1s
AS
SELECT
  window_start AS time,
  product_id,
  open, high, low, close,
  volume, buy_volume, sell_volume, trade_count,
  best_bid, best_ask, best_bid_size, best_ask_size,
  best_ask - best_bid                        AS spread,
  total_cost / (volume + 0.0001)             AS vwap
FROM (
  SELECT
    window_start,
    product_id,
    earliest(price)                          AS open,
    max(price)                               AS high,
    min(price)                               AS low,
    latest(price)                            AS close,
    sum(last_size)                           AS volume,
    sum(if(side = 'buy',  last_size, 0))     AS buy_volume,
    sum(if(side = 'sell', last_size, 0))     AS sell_volume,
    count(*)                                 AS trade_count,
    latest(best_bid)                         AS best_bid,
    latest(best_ask)                         AS best_ask,
    latest(best_bid_size)                    AS best_bid_size,
    latest(best_ask_size)                    AS best_ask_size,
    sum(price * last_size)                   AS total_cost
  FROM tumble({{ .DB }}.coinbase_tickers, 1s)
  GROUP BY window_start, product_id
);
