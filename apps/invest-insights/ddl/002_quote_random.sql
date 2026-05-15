CREATE RANDOM STREAM IF NOT EXISTS {{ .DB }}.quote_random
(
  security_idx uint32  DEFAULT rand() % 200,
  price_delta  float64 DEFAULT rand() % 10
)
SETTINGS eps = {{ .Config.quote_eps }};
