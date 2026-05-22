CREATE VIEW IF NOT EXISTS {{ .DB }}.v_alpha_trade_flow AS
SELECT
  product_id,
  time,
  close,
  buy_volume,
  sell_volume,
  array_sum(lags(buy_volume,  0, 19))                                     AS buy_vol_20s,
  array_sum(lags(sell_volume, 0, 19))                                     AS sell_vol_20s,
  (array_sum(lags(buy_volume, 0, 19)) - array_sum(lags(sell_volume, 0, 19)))
    / (array_sum(lags(volume, 0, 19)) + 0.0001)                          AS trade_flow_alpha
FROM {{ .DB }}.coinbase_1s
PARTITION BY product_id;
