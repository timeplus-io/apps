CREATE MATERIALIZED VIEW IF NOT EXISTS {{ .DB }}.mv_overall_baseline
INTO {{ .DB }}.sig_overall_baseline_mut
AS
SELECT
    src_ip,
    avg(sum_bytes) AS avg_baseline_bytes
FROM (
    SELECT
        window_start AS w_start,
        src_ip,
        sum(bytes) AS sum_bytes
    FROM tumble({{ .DB }}.v_asa_logs, 5s)
    WHERE src_ip IS NOT NULL
    GROUP BY window_start, src_ip
)
GROUP BY src_ip
