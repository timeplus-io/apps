CREATE VIEW IF NOT EXISTS {{ .DB }}.v_dbip_city_ipv4_with_cidr
AS
WITH
  ip_range_start,
  ip_range_end,
  bit_xor(to_ipv4(ip_range_start), to_ipv4(ip_range_end))      AS xor,
  if(xor != 0, ceil(log2(xor)), 0)                             AS unmatched,
  32 - unmatched                                               AS cidr_suffix,
  cast(bit_and(bit_not(pow(2, unmatched) - 1),
               to_ipv4(ip_range_start)), 'uint32')             AS bitand,
  to_ipv4(ipv4_num_to_string(bitand))                          AS cidr_address
SELECT
  concat(to_string(cidr_address), '/', to_string(cidr_suffix)) AS cidr,
  to_ipv4(ip_range_start)                                      AS ip_range_start,
  to_ipv4(ip_range_end)                                        AS ip_range_end,
  latitude,
  longitude,
  country_code,
  state1,
  city
FROM table({{ .DB }}.dbip_city_ipv4);