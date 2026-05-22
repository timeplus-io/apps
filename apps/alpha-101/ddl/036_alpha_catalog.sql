CREATE MUTABLE STREAM IF NOT EXISTS {{ .DB }}.alpha_catalog
(
  alpha_name  string,
  description string,
  equation    string
)
PRIMARY KEY alpha_name
