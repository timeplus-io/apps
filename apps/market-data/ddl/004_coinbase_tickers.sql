CREATE STREAM IF NOT EXISTS {{ .DB }}.coinbase_tickers
(
  `best_ask`      float64,
  `product_id`    string,
  `price`         float64,
  `trade_id`      float64,
  `best_bid`      float64,
  `open_24h`      float64,
  `sequence`      float64,
  `volume_30d`    float64,
  `high_24h`      float64,
  `low_24h`       float64,
  `last_size`     float64,
  `side`          string,
  `time`          string,
  `type`          string,
  `volume_24h`    float64,
  `best_ask_size` float64,
  `best_bid_size` float64
)
TTL to_datetime(_tp_time) + INTERVAL 24 HOUR
SETTINGS logstore_retention_bytes = '107374182', logstore_retention_ms = '300000';
