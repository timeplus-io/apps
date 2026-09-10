CREATE STREAM IF NOT EXISTS {{ .DB }}.otel_metrics_gauge
(
  resource_attributes             map(low_cardinality(string), string)         CODEC(ZSTD(1)),
  resource_schema_url             string                                       CODEC(ZSTD(1)),
  scope_name                      string                                       CODEC(ZSTD(1)),
  scope_version                   string                                       CODEC(ZSTD(1)),
  scope_attributes                map(low_cardinality(string), string)         CODEC(ZSTD(1)),
  scope_dropped_attr_count        uint32                                       CODEC(ZSTD(1)),
  scope_schema_url                string                                       CODEC(ZSTD(1)),
  service_name                    low_cardinality(string)                      CODEC(ZSTD(1)),
  metric_name                     string                                       CODEC(ZSTD(1)),
  metric_description              string                                       CODEC(ZSTD(1)),
  metric_unit                     string                                       CODEC(ZSTD(1)),
  attributes                      map(low_cardinality(string), string)         CODEC(ZSTD(1)),
  start_time_unix                 datetime64(9)                                CODEC(Delta(8), ZSTD(1)),
  time_unix                       datetime64(9)                                CODEC(Delta(8), ZSTD(1)),
  value                           float64                                      CODEC(ZSTD(1)),
  flags                           uint32                                       CODEC(ZSTD(1)),
  `exemplars.filtered_attributes` array(map(low_cardinality(string), string))  CODEC(ZSTD(1)),
  `exemplars.time_unix`           array(datetime64(9))                         CODEC(ZSTD(1)),
  `exemplars.value`               array(float64)                               CODEC(ZSTD(1)),
  `exemplars.span_id`             array(string)                                CODEC(ZSTD(1)),
  `exemplars.trace_id`            array(string)                                CODEC(ZSTD(1))
)
