CREATE VIEW IF NOT EXISTS {{ .DB }}.v_features_alpha_4 AS
SELECT
  time,
  stock_id,
  low,
  (close - close_lag1) / null_if(close_lag1, 0) AS returns
FROM (
  SELECT
    time, stock_id, low, close,
    array_element(lags(close, 1, 1), 1) AS close_lag1
  FROM {{ .DB }}.v_bars
  PARTITION BY stock_id
)
