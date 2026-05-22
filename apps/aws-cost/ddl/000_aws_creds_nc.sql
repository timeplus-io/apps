-- Holds AWS credentials out-of-band so they never appear in
-- `SHOW CREATE EXTERNAL STREAM`. The pollers reference this collection via
-- `SETTINGS named_collection=...`; Proton injects the value into
-- `init_function_parameters` at read time, and the Python init hook parses
-- the JSON and stashes the keys in module globals.
CREATE NAMED COLLECTION IF NOT EXISTS aws_cost_creds AS
  init_function_parameters = '{"access_key_id":{{ .Config.aws_access_key_id | quote }},"secret_access_key":{{ .Config.aws_secret_access_key | quote }}}'
  NOT OVERRIDABLE;
