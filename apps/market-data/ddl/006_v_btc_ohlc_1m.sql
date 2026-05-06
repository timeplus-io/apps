CREATE VIEW IF NOT EXISTS {{ .DB }}.v_coinbase_btc_ohlc_1m
AS
SELECT
  window_start,
  earliest(price) AS open,
  latest(price)   AS close,
  max(price)      AS high,
  min(price)      AS low
FROM tumble({{ .DB }}.coinbase_tickers, 1m)
WHERE product_id = 'BTC-USD'
  AND _tp_time > (now() - 1h)
GROUP BY window_start;
