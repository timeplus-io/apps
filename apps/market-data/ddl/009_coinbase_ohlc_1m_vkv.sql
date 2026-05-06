CREATE MUTABLE STREAM IF NOT EXISTS {{ .DB }}.coinbase_ohlc_1m_vkv
(
  `time`     datetime64(3),
  `symbol`   string,
  `open`     float32,
  `close`    float32,
  `high`     float32,
  `low`      float32,
  `_tp_time` datetime64(3, 'UTC') DEFAULT now64(3, 'UTC')
)
PRIMARY KEY (time, symbol);
