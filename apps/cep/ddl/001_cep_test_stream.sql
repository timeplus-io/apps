CREATE RANDOM STREAM IF NOT EXISTS {{ .DB }}.cep_test_stream
(
  `time`     datetime64(3) DEFAULT now64(),
  `event`    string DEFAULT ['A', 'B', 'C'][(rand() % 3) + 1],
  `_tp_time` datetime64(3, 'UTC') DEFAULT now64(3, 'UTC') CODEC(DoubleDelta, ZSTD(1)),
  `_tp_sn`   int64 CODEC(Delta(8), ZSTD(1)),
  INDEX _tp_time_index _tp_time TYPE minmax GRANULARITY 32,
  INDEX _tp_sn_index _tp_sn TYPE minmax GRANULARITY 32
)
SETTINGS eps = 5
