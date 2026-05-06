CREATE OR REPLACE VIEW {{ .DB }}.v_alpha_price_acceleration AS
SELECT
  product_id,
  time,
  close,
  (close - array_element(lags(close, 1, 1), 1))                          AS velocity_now,
  (array_element(lags(close, 1, 1), 1) - array_element(lags(close, 2, 2), 1))
                                                                           AS velocity_prev,
  ((close - array_element(lags(close, 1, 1), 1))
   - (array_element(lags(close, 1, 1), 1) - array_element(lags(close, 2, 2), 1)))
    / close                                                                AS acceleration_alpha
FROM {{ .DB }}.coinbase_1s
PARTITION BY product_id;
