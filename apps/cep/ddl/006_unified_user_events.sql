CREATE VIEW IF NOT EXISTS {{ .DB }}.unified_user_events
(
  `eventType`     string,
  `userId`        string,
  `amount`        float64,
  `location`      string,
  `timestamp`     datetime64(3),
  `source_stream` string
) AS
SELECT
  eventType, userId, 0. AS amount, location, timestamp, eventType AS source_stream
FROM
  {{ .DB }}.login_events
UNION ALL
SELECT
  eventType, userId, amount, location, timestamp, eventType AS source_stream
FROM
  {{ .DB }}.purchase_events
