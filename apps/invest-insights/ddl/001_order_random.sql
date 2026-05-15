CREATE RANDOM STREAM IF NOT EXISTS {{ .DB }}.order_random
(
  order_idx  uint32  DEFAULT rand() % 40000000000,
  account_idx int32  DEFAULT rand() % 200,
  security_idx uint32 DEFAULT rand() % 200,
  strategy_idx uint8  DEFAULT rand() % 8,
  side        int8   DEFAULT rand() % 10,
  price_delta float64 DEFAULT rand() % 10
)
SETTINGS eps = {{ .Config.order_eps }};
