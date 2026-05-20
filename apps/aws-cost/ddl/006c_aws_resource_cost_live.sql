CREATE MUTABLE STREAM IF NOT EXISTS {{ .DB }}.aws_resource_cost_live (
  resource_id       string,
  service           string,
  region            string,
  resource_type     string,
  state             string,
  creator           string,
  size_units        float64,
  unit              string,
  tags_json         string,
  snapshot_ts       datetime64(3),
  unit_hourly_usd   float64,
  hourly_cost_usd   float64,
  monthly_cost_usd  float64,
  PRIMARY KEY (resource_id)
);
