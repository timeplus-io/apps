CREATE MATERIALIZED VIEW IF NOT EXISTS {{ .DB }}.mv_live_5s_traffic
INTO {{ .DB }}.sig_live_5s_traffic
AS
SELECT
    src_ip,
    sum(bytes) AS live_bytes,
    window_start AS w_start,
    window_end   AS w_end
FROM hop({{ .DB }}.v_asa_logs, 1s, 5s)
WHERE src_ip IS NOT NULL
GROUP BY src_ip, window_start, window_end
