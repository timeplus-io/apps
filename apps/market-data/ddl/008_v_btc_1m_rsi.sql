CREATE VIEW IF NOT EXISTS {{ .DB }}.v_coinbase_btc_1m_rsi
AS
SELECT
  time,
  lags(ret, 1, 14)                                           AS rets,
  array_avg(array_map(x -> if(x > 0, x, 0), rets))          AS avg_gains,
  array_avg(array_map(x -> if(x > 0, 0, -x), rets))         AS avg_losses,
  avg_gains / avg_losses                                     AS RS,
  100 - (100 / (1 + RS))                                     AS RSI
FROM {{ .DB }}.v_coinbase_btc_1m_ret;
