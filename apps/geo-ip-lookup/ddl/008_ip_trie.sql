CREATE DICTIONARY IF NOT EXISTS {{ .DB }}.ip_trie
(
  `cidr`         string,
  `latitude`     float64,
  `longitude`    float64,
  `country_code` string,
  `state`        string,
  `city`         string
)
PRIMARY KEY cidr
SOURCE(TIMEPLUS(
  STREAM   'geoip_lookup'
  USER     '{{ .Config.dict_user }}'
  PASSWORD '{{ .Config.dict_password }}'
))
LIFETIME(MIN 0 MAX 3600)
LAYOUT(IP_TRIE);