CREATE OR REPLACE VIEW {{ .DB }}.v_alpha_mean_reversion AS
SELECT
  product_id,
  time,
  close,
  array_avg(lags(close, 1, 20))                          AS ma_20s,
  (close - array_avg(lags(close, 1, 20)))
    / array_avg(lags(close, 1, 20))                      AS deviation,
  -1 * (close - array_avg(lags(close, 1, 20)))
    / array_avg(lags(close, 1, 20))                      AS mean_reversion_alpha
FROM {{ .DB }}.coinbase_1s
PARTITION BY product_id;
