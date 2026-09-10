CREATE MATERIALIZED VIEW IF NOT EXISTS {{ .DB }}.mv_rule_rp004
INTO {{ .DB }}.agentguard_security_events
AS -- Changelog v1.3.0 (2026-04-19):
-- CRITICAL FIX: git clone lookahead (?!github.com|...) used PCRE negative lookahead
--   which is NOT supported in RE2/Timeplus. Replaced with:
--   match(..., 'git\s+clone\s+https?://[a-z0-9]') AND NOT LIKE '%github.com%'
--   AND NOT LIKE '%gitlab.com%' AND NOT LIKE '%bitbucket.org%' AND NOT LIKE '%codeberg.org%'
-- ADDED: gem install (Ruby), go install (Go), composer require (PHP) — all used by
--   coding agents; MCP server installs via these ecosystems documented in Sigilsec 2026.
-- ADDED: npx @scope/pkg pattern — LLM coding agents install scoped npm packages via npx;
--   non-standard @scope/ (not @modelcontextprotocol/, @anthropic-ai/, etc.) is suspicious.
-- REFERENCES: Added agentfred.ai LiteLLM attack writeup.
-- Changelog v1.1.0 (2026-04-16):
-- Added uv, pipx, poetry, pnpm package managers.
-- Added curl-pipe-bash / wget-pipe-sh (direct script execution).
-- Added git clone from non-github/gitlab hosts (typosquat/malicious repo).
-- Added docker pull from non-standard registry.
-- Added pip install with --index-url or --extra-index-url (typosquat vector).
-- Retained all original patterns unchanged.
-- fp_rate improved from high to medium by adding source-context conditions.
SELECT
  event_time           AS detected_at,
  'rp-004'             AS rule_id,
  'Supply Chain Watch' AS rule_name,
  'warning'            AS severity,
  agent_id,
  deployment_id,
  session_id,
  run_id,
  raw_hook_name        AS hook_name,
  tool_name,
  concat('Package install/script exec by agent ', agent_id,
    ' via ', if(tool_name != '', tool_name, raw_hook_name)) AS message,
  raw_event_data       AS event_data
FROM {{ .DB }}.agentguard_cim_event
WHERE event_type = 'tool_invoke'
  AND (
    -- Original package managers (retained)
       lower(tool_input) LIKE '%npm install%'
    OR lower(tool_input) LIKE '%pip install%'
    OR lower(tool_input) LIKE '%yarn add%'
    OR lower(tool_input) LIKE '%cargo install%'
    OR lower(tool_input) LIKE '%apt-get install%'
    OR lower(tool_input) LIKE '%brew install%'
    -- Additional package managers (v1.1.0)
    OR lower(tool_input) LIKE '%uv add%'
    OR lower(tool_input) LIKE '%pipx install%'
    OR lower(tool_input) LIKE '%poetry add%'
    OR lower(tool_input) LIKE '%pnpm add%'
    -- Additional package managers (v1.3.0): Ruby, Go, PHP
    OR match(lower(tool_input), 'gem\s+install\s+')
    OR match(lower(tool_input), 'go\s+install\s+')
    OR match(lower(tool_input), 'composer\s+require\s+')
    -- npx scoped package install (v1.3.0) — coding agents installing MCP tools
    -- Pattern: npx @scope/pkg (any scope) in tool_input for shell/bash tools
    OR match(lower(tool_input), 'npx\s+[^@\s]*@[a-z0-9][a-z0-9\-]+')
    -- Direct script execution via curl/wget pipe (v1.1.0 — high risk)
    OR match(lower(tool_input), 'curl.{0,100}\|\s*(ba)?sh')
    OR match(lower(tool_input), 'wget.{0,100}\|\s*(ba)?sh')
    -- pip with alternate index (typosquatting vector — LiteLLM attack, v1.1.0)
    OR match(lower(tool_input), 'pip\s+install.{0,100}--(?:extra-)?index-url')
    -- git clone from non-standard host (v1.1.0, RE2-fixed v1.3.0)
    -- RE2 does not support (?!...) lookahead; use NOT LIKE for trusted host exclusion
    OR (
      match(lower(tool_input), 'git\s+clone\s+https?://[a-z0-9]')
      AND lower(tool_input) NOT LIKE '%github.com%'
      AND lower(tool_input) NOT LIKE '%gitlab.com%'
      AND lower(tool_input) NOT LIKE '%bitbucket.org%'
      AND lower(tool_input) NOT LIKE '%codeberg.org%'
    )
    -- docker pull from non-standard registry (v1.1.0)
    OR match(lower(tool_input), 'docker\s+pull\s+[a-z0-9][a-z0-9.\-]*/[a-z0-9\-]+:[a-z0-9.\-]+')
  )
