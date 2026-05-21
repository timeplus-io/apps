CREATE OR REPLACE VIEW {{ .DB }}.v_features_alpha_2 AS
SELECT
  time,
  stock_id,
  open,
  close,
  volume,
  (close - open) / null_if(open, 0)                          AS intraday_ret,
  log(null_if(volume, 0)) - log(null_if(vol_lag2, 0))        AS log_vol_delta_2,
  (close - close_lag1) / null_if(close_lag1, 0)              AS returns
FROM (
  SELECT
    time, stock_id, open, close, volume,
    array_element(lags(volume, 2, 2), 1) AS vol_lag2,
    array_element(lags(close, 1, 1), 1)  AS close_lag1
  FROM {{ .DB }}.v_bars
  PARTITION BY stock_id
)
