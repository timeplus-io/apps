CREATE STREAM IF NOT EXISTS {{ .DB }}.agentguard_rules
(
  rule_id                  low_cardinality(string),
  snapshot_id              string,
  revision                 uint64,
  name                     string,
  definition_version       string,
  definition_hash          string,
  description              string,
  rendered_sql             string,
  deployed_udfs_json       string,
  parameter_overrides_json string,
  enabled                  bool,
  deleted                  bool,
  severity                 low_cardinality(string),
  category                 low_cardinality(string),
  required_telemetry       string,
  fp_rate                  low_cardinality(string),
  hook_sources             string,
  block_policy             low_cardinality(string),
  update_reason            low_cardinality(string),
  updated_by               string,
  updated_at               datetime64(9)
)
