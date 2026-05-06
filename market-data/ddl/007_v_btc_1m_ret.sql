CREATE VIEW IF NOT EXISTS {{ .DB }}.v_coinbase_btc_1m_ret
AS
SELECT
  window_start                        AS time,
  close,
  lag(close)                          AS prev_close,
  (close - prev_close) / prev_close   AS ret
FROM {{ .DB }}.v_coinbase_btc_ohlc_1m
WHERE prev_close > 0;
