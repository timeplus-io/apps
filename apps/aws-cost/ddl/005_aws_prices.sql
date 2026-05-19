CREATE MUTABLE STREAM IF NOT EXISTS {{ .DB }}.aws_prices (
  service        string,
  region         string,
  resource_type  string,
  unit           string,
  hourly_usd     float64,
  effective_ts   datetime64(3),
  PRIMARY KEY (service, region, resource_type, unit)
);
