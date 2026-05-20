CREATE MUTABLE STREAM IF NOT EXISTS {{ .DB }}.aws_resource_usage_live (
  resource_id    string,
  service        string,
  region         string,
  resource_type  string,
  state          string,
  creator        string,
  size_units     float64,
  unit           string,
  tags_json      string,
  snapshot_ts    datetime64(3),
  PRIMARY KEY (resource_id)
);
