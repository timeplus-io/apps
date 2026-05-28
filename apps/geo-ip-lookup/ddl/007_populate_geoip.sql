INSERT INTO {{ .DB }}.geoip_lookup (cidr, latitude, longitude, country_code, state, city)
SELECT
  cidr,
  latitude,
  longitude,
  coalesce(country_code, '') AS country_code,
  coalesce(state1,       '') AS state,
  coalesce(city,         '') AS city
FROM {{ .DB }}.v_dbip_city_ipv4_with_cidr;