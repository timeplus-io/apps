CREATE RANDOM STREAM IF NOT EXISTS {{ .DB }}.random_market_data
(
  `time`     datetime64(3, 'UTC') DEFAULT now64(3, 'UTC'),
  `stock_id` string DEFAULT 'STOCK_' || to_string(rand(0) % {{ .Config.num_stocks }}),
  `price`    float64 DEFAULT round(
    array_element(
      [50.0, 80.0, 120.0, 200.0, 350.0, 500.0, 750.0, 1000.0, 1500.0, 2500.0],
      (rand(0) % {{ .Config.num_stocks }}) + 1
    ) * (1 + rand_normal(0.0, 0.005)),
    4)
)
SETTINGS eps = 100
