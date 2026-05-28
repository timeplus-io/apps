CREATE MUTABLE STREAM IF NOT EXISTS {{ .DB }}.dbip_city_ipv4
(
  `ip_range_start` ipv4,
  `ip_range_end`   ipv4,
  `country_code`   nullable(string),
  `state1`         nullable(string),
  `state2`         nullable(string),
  `city`           nullable(string),
  `postcode`       nullable(string),
  `latitude`       float64,
  `longitude`      float64,
  `timezone`       nullable(string)
)
PRIMARY KEY (ip_range_start, ip_range_end);