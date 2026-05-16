CREATE MATERIALIZED VIEW IF NOT EXISTS {{ .DB }}.mv_hourly_baseline
INTO {{ .DB }}.sig_hourly_baseline_mut
AS
SELECT
    src_ip,
    hour_of_day,
    avg(sum_bytes) AS avg_baseline_bytes
FROM (
    SELECT
        window_start AS w_start,
        src_ip,
        hour(window_start) AS hour_of_day,
        sum(bytes) AS sum_bytes
    FROM tumble({{ .DB }}.v_asa_logs, 5s)
    WHERE src_ip IS NOT NULL
    GROUP BY src_ip, window_start
)
GROUP BY src_ip, hour_of_day
