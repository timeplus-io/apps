CREATE RANDOM STREAM IF NOT EXISTS {{ .DB }}.quote_random
(
  -- Distinct rand(seed) per column — see 001_order_random.sql
  security_idx uint32  DEFAULT rand(1) % 200,
  price_delta  float64 DEFAULT rand(2) % 10
)
SETTINGS eps = {{ .Config.quote_eps }};
