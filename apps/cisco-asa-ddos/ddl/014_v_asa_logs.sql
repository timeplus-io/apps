CREATE VIEW IF NOT EXISTS {{ .DB }}.v_asa_logs
AS
SELECT
    _tp_time,
    device_name,
    severity,
    message_id,
    asa_message,
    src_ip,
    dst_ip,
    bytes
FROM {{ .DB }}.flatten_extracted_asa_logs
WHERE bytes IS NOT NULL
