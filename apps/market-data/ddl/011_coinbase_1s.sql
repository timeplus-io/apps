CREATE STREAM IF NOT EXISTS {{ .DB }}.coinbase_1s
(
  `time`          datetime64(3, 'UTC'),
  `product_id`    string,
  `open`          float64,
  `high`          float64,
  `low`           float64,
  `close`         float64,
  `volume`        float64,
  `buy_volume`    float64,
  `sell_volume`   float64,
  `trade_count`   uint64,
  `best_bid`      float64,
  `best_ask`      float64,
  `best_bid_size` float64,
  `best_ask_size` float64,
  `spread`        float64,
  `vwap`          float64
)
PARTITION BY to_start_of_hour(_tp_time)
TTL to_datetime(_tp_time) + INTERVAL 4 HOUR
SETTINGS index_granularity = 8192,
         logstore_retention_bytes = '107374182',
         logstore_retention_ms = '300000';
