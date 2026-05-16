CREATE MUTABLE STREAM IF NOT EXISTS {{ .DB }}.sig_overall_baseline_mut (
    src_ip              ipv4,
    avg_baseline_bytes  float64
)
PRIMARY KEY src_ip
