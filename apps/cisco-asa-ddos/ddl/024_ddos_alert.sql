CREATE ALERT IF NOT EXISTS {{ .DB }}.ddos_alert
BATCH 10 EVENTS WITH TIMEOUT 5s
LIMIT 1 ALERTS PER 30s
CALL send_ddos_alert
AS
SELECT
    'DDoS Attack Detected' AS title,
    concat(
        'Source IP: ', to_string(src_ip), '\n',
        'Live Traffic (5s): ', format_readable_size(live_bytes), '\n',
        'Overall Spike Ratio: ', to_string(round(overall_spike_ratio, 2)), 'x',
        CASE WHEN overall_spike_ratio > {{ .Config.spike_threshold }} THEN ' EXCEEDED' ELSE '' END, '\n',
        'Hourly Spike Ratio: ', to_string(round(hourly_spike_ratio, 2)), 'x',
        CASE WHEN hourly_spike_ratio > {{ .Config.spike_threshold }} THEN ' EXCEEDED' ELSE '' END, '\n',
        'Time: ', to_string(now())
    ) AS content,
    'high' AS severity
FROM {{ .DB }}.cxt_ddos_stream
WHERE overall_spike_ratio > {{ .Config.spike_threshold }} OR hourly_spike_ratio > {{ .Config.spike_threshold }}
