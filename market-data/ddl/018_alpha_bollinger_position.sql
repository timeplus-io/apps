CREATE OR REPLACE VIEW {{ .DB }}.v_alpha_bollinger_position AS
SELECT
  product_id,
  time,
  close,
  array_avg(lags(close, 1, 20))                                           AS mean_20s,
  sqrt(array_avg(
    array_map(x -> pow(x - array_avg(lags(close, 1, 20)), 2), lags(close, 1, 20))
  ))                                                                       AS std_dev,
  (close - array_avg(lags(close, 1, 20)))
    / (2 * sqrt(array_avg(
        array_map(x -> pow(x - array_avg(lags(close, 1, 20)), 2), lags(close, 1, 20))
      )) + 0.0001)                                                         AS bollinger_position_alpha
FROM {{ .DB }}.coinbase_1s
PARTITION BY product_id;
