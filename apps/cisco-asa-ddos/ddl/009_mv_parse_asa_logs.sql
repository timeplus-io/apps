CREATE MATERIALIZED VIEW IF NOT EXISTS {{ .DB }}.mv_parse_asa_logs
INTO {{ .DB }}.parsed_asa_logs
AS
SELECT
    now64(3) AS ingestion_time,
    to_string(base_fields['timestamp']) AS log_timestamp,
    to_string(base_fields['device_name']) AS device_name,
    to_int8_or_null(base_fields['severity']) AS severity,
    to_string(base_fields['message_id']) AS message_id,
    to_string(base_fields['asa_message']) AS asa_message
FROM (
    SELECT
        message,
        grok(message, '<%{POSINT:priority}>%{DATA:timestamp} %{HOSTNAME:device_name} %%{WORD:facility}-%{INT:severity}-%{INT:message_id}: %{GREEDYDATA:asa_message}') AS base_fields
    FROM {{ .DB }}.asa_logs_stream
)
WHERE base_fields['message_id'] IS NOT NULL
