CREATE TASK IF NOT EXISTS {{ .DB }}.refresh_pre_value
SCHEDULE INTERVAL {{ .Config.pre_value_schedule_hours }} HOUR
TIMEOUT INTERVAL {{ .Config.pre_value_timeout_minutes }} MINUTE
INTO {{ .DB }}.pre_value
AS SELECT
    a.SecurityAccount,
    a.SecurityId,
    sum(b.LastPx * a.HoldingQty) AS prevalue
FROM table({{ .DB }}.position) AS a
JOIN table({{ .DB }}.stock) AS b ON a.SecurityId = b.SecurityID
GROUP BY SecurityAccount, SecurityId;
