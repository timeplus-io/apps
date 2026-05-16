CREATE MATERIALIZED VIEW IF NOT EXISTS {{ .DB }}.mv_asa_logs_background
INTO {{ .DB }}.asa_logs_stream
AS
SELECT log_message AS message
FROM {{ .DB }}.cisco_asa_background_gen
