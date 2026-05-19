CREATE STREAM IF NOT EXISTS {{ .DB }}.aws_resources (
  service        string,
  region         string,
  resource_id    string,
  resource_type  string,
  state          string,
  size_units     float64,
  unit           string,
  tags_json      string,
  creator        string,
  snapshot_ts    datetime64(3)
)
TTL to_datetime(snapshot_ts) + INTERVAL 7 DAY;
