CREATE VIEW IF NOT EXISTS {{ .DB }}.v_alpha_composite AS
SELECT
  product_id,
  time,
  close,
  (close - array_element(lags(close, 3, 3), 1))
    / array_element(lags(close, 3, 3), 1)                                 AS momentum,
  -1 * (close - array_avg(lags(close, 1, 20)))
    / array_avg(lags(close, 1, 20))                                       AS mean_rev,
  (best_bid_size - best_ask_size)
    / (best_bid_size + best_ask_size + 0.0001)                            AS book_imb,
  (buy_volume - sell_volume)
    / (volume + 0.0001)                                                    AS flow,
  (
    (close - array_element(lags(close, 3, 3), 1)) / array_element(lags(close, 3, 3), 1)
    + (-1 * (close - array_avg(lags(close, 1, 20))) / array_avg(lags(close, 1, 20)))
    + (best_bid_size - best_ask_size) / (best_bid_size + best_ask_size + 0.0001)
    + (buy_volume - sell_volume) / (volume + 0.0001)
  ) / 4                                                                    AS composite_alpha
FROM {{ .DB }}.coinbase_1s
PARTITION BY product_id;
