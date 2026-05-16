CREATE MATERIALIZED VIEW IF NOT EXISTS {{ .DB }}.mv_enhanced_asa_logs
INTO {{ .DB }}.flatten_extracted_asa_logs
AS
SELECT *
FROM {{ .DB }}.v_flatten_asa_logs
