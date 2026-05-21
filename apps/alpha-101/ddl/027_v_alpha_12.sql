CREATE OR REPLACE VIEW {{ .DB }}.v_alpha_12 AS
SELECT
  time,
  stock_id,
  (close - close_lag1) / null_if(close_lag1, 0)                          AS returns,
  sign(cast(volume, 'int64') - cast(volume_lag1, 'int64'))
    * (-1 * (close - close_lag1))                                        AS alpha_12
FROM (
  SELECT
    time, stock_id, close, volume,
    array_element(lags(close, 1, 1), 1)  AS close_lag1,
    array_element(lags(volume, 1, 1), 1) AS volume_lag1
  FROM {{ .DB }}.v_bars
  PARTITION BY stock_id
)
