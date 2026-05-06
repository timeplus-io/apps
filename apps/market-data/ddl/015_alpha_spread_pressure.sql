CREATE OR REPLACE VIEW {{ .DB }}.v_alpha_spread_pressure AS
SELECT
  product_id,
  time,
  close,
  best_bid,
  best_ask,
  spread * 10000 / close                                  AS spread_bps,
  (close - (best_bid + best_ask) / 2)
    / (spread + 0.0001)                                   AS trade_location_alpha,
  (best_bid_size - best_ask_size)
    / (best_bid_size + best_ask_size + 0.0001)            AS book_imbalance_alpha
FROM {{ .DB }}.coinbase_1s
PARTITION BY product_id;
