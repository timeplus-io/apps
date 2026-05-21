CREATE OR REPLACE VIEW {{ .DB }}.v_alpha_41 AS
SELECT
  time,
  stock_id,
  (close - close_lag1) / null_if(close_lag1, 0)  AS returns,
  sqrt(high * low) - vwap                         AS alpha_41
FROM (
  SELECT
    time, stock_id, high, low, close, vwap,
    array_element(lags(close, 1, 1), 1) AS close_lag1
  FROM {{ .DB }}.v_bars
  PARTITION BY stock_id
)
