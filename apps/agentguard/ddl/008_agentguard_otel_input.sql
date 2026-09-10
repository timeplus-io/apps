CREATE INPUT IF NOT EXISTS {{ .DB }}.agentguard_otel_input
SETTINGS
  type                            = 'otel',
  protocol                        = 'http',
  tcp_port                        = {{ .Config.otel_port }},
  listen_host                     = '{{ .Config.otel_listen_host }}',
  traces_target_stream                        = '{{ .DB }}.otel_traces',
  logs_target_stream                          = '{{ .DB }}.otel_logs',
  metrics_gauge_target_stream                 = '{{ .DB }}.otel_metrics_gauge',
  metrics_sum_target_stream                   = '{{ .DB }}.otel_metrics_sum',
  metrics_histogram_target_stream             = '{{ .DB }}.otel_metrics_histogram',
  metrics_exponential_histogram_target_stream = '{{ .DB }}.otel_metrics_exponential_histogram',
  metrics_summary_target_stream               = '{{ .DB }}.otel_metrics_summary'
COMMENT 'OpenClaw agent telemetry via OTLP/HTTP'
