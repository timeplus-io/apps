CREATE MATERIALIZED VIEW IF NOT EXISTS {{ .DB }}.mv_ohlc_by_symbol
INTO {{ .DB }}.coinbase_ohlc_1m_vkv
AS
SELECT
  window_start    AS time,
  product_id      AS symbol,
  earliest(price) AS open,
  latest(price)   AS close,
  max(price)      AS high,
  min(price)      AS low
FROM tumble({{ .DB }}.coinbase_tickers, 1m)
WHERE _tp_time > (now() - 1h)
GROUP BY window_start, product_id
EMIT STREAM PERIODIC 250ms;
