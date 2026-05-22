CREATE OR REPLACE VIEW {{ .DB }}.v_features_alpha_9 AS
SELECT
  time,
  stock_id,
  close,
  close - close_lag1                            AS delta_close_1,
  (close - close_lag1) / null_if(close_lag1, 0) AS returns
FROM (
  SELECT
    time, stock_id, close,
    array_element(lags(close, 1, 1), 1) AS close_lag1
  FROM {{ .DB }}.v_bars
  PARTITION BY stock_id
)
