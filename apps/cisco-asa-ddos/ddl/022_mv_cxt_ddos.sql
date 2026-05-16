CREATE MATERIALIZED VIEW IF NOT EXISTS {{ .DB }}.mv_cxt_ddos
INTO {{ .DB }}.cxt_ddos_stream
AS
SELECT
    l.src_ip AS src_ip,
    l.live_bytes AS live_bytes,
    o.avg_baseline_bytes AS overall_baseline,
    h.avg_baseline_bytes AS hourly_baseline,
    l.live_bytes / o.avg_baseline_bytes AS overall_spike_ratio,
    l.live_bytes / h.avg_baseline_bytes AS hourly_spike_ratio
FROM {{ .DB }}.sig_live_5s_traffic l
JOIN {{ .DB }}.sig_overall_baseline_mut o ON l.src_ip = o.src_ip
JOIN {{ .DB }}.sig_hourly_baseline_mut h
    ON l.src_ip = h.src_ip
    AND h.hour_of_day = hour(l._tp_time)
