CREATE VIEW IF NOT EXISTS {{ .DB }}.v_alpha_vwap AS
SELECT
  product_id,
  time,
  close,
  vwap,
  array_sum(array_map(
    (p, v) -> p * v,
    lags(vwap, 0, 19),
    lags(volume, 0, 19)
  )) / (array_sum(lags(volume, 0, 19)) + 0.0001)                          AS vwap_20s,
  (close - array_sum(array_map(
    (p, v) -> p * v,
    lags(vwap, 0, 19),
    lags(volume, 0, 19)
  )) / (array_sum(lags(volume, 0, 19)) + 0.0001))
    / close                                                                AS vwap_alpha
FROM {{ .DB }}.coinbase_1s
PARTITION BY product_id;
