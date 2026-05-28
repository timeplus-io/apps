INSERT INTO {{ .DB }}.dbip_city_ipv4
  (ip_range_start, ip_range_end, country_code, state1, state2, city, postcode, latitude, longitude, timezone)
SELECT
  to_ipv4(ip_range_start),
  to_ipv4(ip_range_end),
  country_code, state1, state2, city, postcode, latitude, longitude, timezone
FROM url(
  'https://tp-solutions.s3.us-west-2.amazonaws.com/ip-location-db/dbip-city-ipv4.csv.gz',
  'CSV',
  'ip_range_start ipv4, ip_range_end ipv4, country_code nullable(string), state1 nullable(string), state2 nullable(string), city nullable(string), postcode nullable(string), latitude float64, longitude float64, timezone nullable(string)'
);