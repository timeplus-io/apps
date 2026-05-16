CREATE MUTABLE STREAM IF NOT EXISTS {{ .DB }}.sig_hourly_baseline_mut (
    src_ip              ipv4,
    hour_of_day         uint8,
    avg_baseline_bytes  float64
)
PRIMARY KEY (src_ip, hour_of_day)
