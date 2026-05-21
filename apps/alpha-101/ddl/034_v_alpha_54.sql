CREATE OR REPLACE VIEW {{ .DB }}.v_alpha_54 AS
SELECT
  time,
  stock_id,
  (close - close_lag1) / null_if(close_lag1, 0)                                                        AS returns,
  -1 * (low - close) * pow(open, 5) / null_if((low - high) * pow(close, 5), 0)                         AS alpha_54
FROM (
  SELECT
    time, stock_id, open, high, low, close,
    array_element(lags(close, 1, 1), 1) AS close_lag1
  FROM {{ .DB }}.v_bars
  PARTITION BY stock_id
)
