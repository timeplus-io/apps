CREATE VIEW IF NOT EXISTS {{ .DB }}.v_alpha_momentum AS
SELECT
  product_id,
  time,
  close,
  (close - array_element(lags(close, 3, 3), 1))
    / array_element(lags(close, 3, 3), 1)                                AS return_3s,
  (close - array_element(lags(close, 10, 10), 1))
    / array_element(lags(close, 10, 10), 1)                              AS return_10s,
  ((close - array_element(lags(close, 3, 3), 1)) / array_element(lags(close, 3, 3), 1))
  - ((close - array_element(lags(close, 10, 10), 1)) / array_element(lags(close, 10, 10), 1))
                                                                          AS momentum_alpha
FROM {{ .DB }}.coinbase_1s
PARTITION BY product_id;
