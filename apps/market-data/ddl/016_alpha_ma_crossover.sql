CREATE OR REPLACE VIEW {{ .DB }}.v_alpha_ma_crossover AS
SELECT
  product_id,
  time,
  close,
  array_avg(lags(close, 0, 4))                            AS ma_5s,
  array_avg(lags(close, 0, 19))                           AS ma_20s,
  (array_avg(lags(close, 0, 4)) - array_avg(lags(close, 0, 19)))
    / array_avg(lags(close, 0, 19))                       AS ma_crossover_alpha
FROM {{ .DB }}.coinbase_1s
PARTITION BY product_id;
