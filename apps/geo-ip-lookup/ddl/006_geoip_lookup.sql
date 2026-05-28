CREATE MUTABLE STREAM IF NOT EXISTS {{ .DB }}.geoip_lookup
(
  `cidr`         string,
  `latitude`     float64,
  `longitude`    float64,
  `country_code` string,
  `state`        string,
  `city`         string
)
PRIMARY KEY cidr;