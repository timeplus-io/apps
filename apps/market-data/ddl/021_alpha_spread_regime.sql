CREATE OR REPLACE VIEW {{ .DB }}.v_alpha_spread_regime AS
SELECT
  product_id,
  time,
  close,
  spread,
  array_avg(lags(spread, 1, 20))                                          AS avg_spread_20s,
  spread / (array_avg(lags(spread, 1, 20)) + 0.0001)                     AS spread_ratio,
  -1 * (spread / (array_avg(lags(spread, 1, 20)) + 0.0001) - 1)         AS spread_regime_alpha
FROM {{ .DB }}.coinbase_1s
PARTITION BY product_id;
