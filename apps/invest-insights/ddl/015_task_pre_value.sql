CREATE TASK IF NOT EXISTS {{ .DB }}.refresh_pre_value
SCHEDULE INTERVAL 5 MINUTE
TIMEOUT INTERVAL 2 MINUTE
INTO {{ .DB }}.pre_value
AS SELECT
    a.SecurityAccount,
    a.SecurityId,
    sum(b.LastPx * a.HoldingQty) AS prevalue
FROM table({{ .DB }}.position) AS a
JOIN table({{ .DB }}.stock) AS b ON a.SecurityId = b.SecurityID
GROUP BY SecurityAccount, SecurityId;
