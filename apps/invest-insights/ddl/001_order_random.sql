CREATE RANDOM STREAM IF NOT EXISTS {{ .DB }}.order_random
(
  -- Each column gets a distinct rand(seed): unseeded rand() is evaluated once
  -- per row and shared across all DEFAULT expressions, which locks the columns
  -- together (e.g. side == security_idx % 10, so a security only ever gets one
  -- order side and the part_rate spread condition can never fire).
  order_idx  uint32  DEFAULT rand(1) % 40000000000,
  account_idx int32  DEFAULT rand(2) % 200,
  security_idx uint32 DEFAULT rand(3) % 200,
  strategy_idx uint8  DEFAULT rand(4) % 8,
  side        int8   DEFAULT rand(5) % 10,
  price_delta float64 DEFAULT rand(6) % 10
)
SETTINGS eps = {{ .Config.order_eps }};
