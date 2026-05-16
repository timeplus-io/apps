CREATE MATERIALIZED VIEW IF NOT EXISTS {{ .DB }}.mv_asa_logs_sim_normal
INTO {{ .DB }}.asa_logs_stream
AS
SELECT log_message AS message
FROM {{ .DB }}.cisco_asa_sim_normal
