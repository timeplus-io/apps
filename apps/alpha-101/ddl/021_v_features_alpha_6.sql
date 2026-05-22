CREATE VIEW IF NOT EXISTS {{ .DB }}.v_features_alpha_6 AS
SELECT
  time,
  stock_id,
  open,
  cast(volume, 'float64')                       AS volume_f,
  (close - close_lag1) / null_if(close_lag1, 0) AS returns
FROM (
  SELECT
    time, stock_id, open, close, volume,
    array_element(lags(close, 1, 1), 1) AS close_lag1
  FROM {{ .DB }}.v_bars
  PARTITION BY stock_id
)
