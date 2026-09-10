CREATE MATERIALIZED VIEW IF NOT EXISTS {{ .DB }}.mv_rule_rp002
INTO {{ .DB }}.agentguard_security_events
AS -- Changelog v1.4.0 (2026-04-19):
-- ADDED ag_dlp_jwt_check() JavaScript UDF: properly validates JWT structure
--   by base64-decoding header and checking for 'alg' field — more precise
--   than the raw regex match on the encoded string which could FP on any
--   three-segment base64url string. UDF replaces the raw JWT regex branch.
-- Changelog v1.1.0 (2026-04-16):
-- Tightened '%api_key%' and '%secret_key%' to regex with word boundaries
--   to avoid matching "api_key_name" or "public_key" in code comments.
-- Added OpenAI key pattern: sk-[a-zA-Z0-9]{32,}.
-- Added Google API key pattern: AIza[0-9A-Za-z\-_]{35}.
-- Added JWT token pattern (three base64url segments separated by dots).
-- Added PEM private key block detection.
-- Added DNS exfiltration: API key embedded as subdomain (PipeLab 2026).
-- Retained original SSN regex and specific token prefix LIKEs (low FP, retain as-is).
--
-- Changelog v1.2.0 (2026-04-17):
-- NEW: Silent Egress sharded exfiltration (arXiv:2602.22450):
--   Base64/URL-encoded query parameter with 20+ chars in outbound URL — captures
--   split-data exfiltration that bypasses single-request content inspection.
--   Pattern: https?://.../<path>?<param>=<base64_20+chars>
--   Test confirmed: 'https://exfil.com/t?q=eyJzZWNyZXQiOiJzb21ldGhpbmcifQ==' → true
--   FP test: 'https://example.com/page?token=abc123' → false (too short, <20 chars)
-- NEW: Instructional text / README injection (arXiv:2603.11862 ReadSecBench):
--   Agent reads malicious README/doc via file-read tool and executes embedded
--   curl/wget/pip/npm commands; detected in tool_result when file-read tool
--   returns download-execute or package-install instruction payloads.
--   Tool name anchor: tool_name matching read/load/fetch/open file patterns
--   Payload anchor: curl|wget pipe-to-shell or pip install in tool_result.
--   fp_rate assessment: combined tool_name + payload requirement → low FP.
SELECT
  event_time     AS detected_at,
  'rp-002'       AS rule_id,
  'DLP Sentinel' AS rule_name,
  'critical'     AS severity,
  agent_id,
  deployment_id,
  session_id,
  run_id,
  raw_hook_name  AS hook_name,
  tool_name,
  concat('Sensitive data in ', raw_hook_name,
    if(tool_name != '', concat(' (', tool_name, ')'), ''),
    ' from agent ', agent_id) AS message,
  raw_event_data AS event_data
FROM {{ .DB }}.agentguard_cim_event
WHERE event_type IN ('tool_complete', 'llm_response')
  AND session_id != ''
  AND (
    -- SSN pattern (original, retained)
       match(concat(tool_result, ' ', assistant_message), '[0-9]{3}-[0-9]{2}-[0-9]{4}')
    -- API key / secret with word boundaries (tightened from broad LIKE)
    OR match(lower(concat(tool_result, ' ', assistant_message)), '\b(api_key|secret_key|access_key)\s*[=:]\s*["\']?[a-z0-9_\-]{8,}')
    -- Bearer token (retained specific LIKE)
    OR lower(concat(tool_result, ' ', assistant_message)) LIKE '%bearer %'
    -- Anthropic key prefix (retained specific LIKE)
    OR lower(concat(tool_result, ' ', assistant_message)) LIKE '%sk-ant-%'
    -- GitHub token (retained specific LIKE)
    OR lower(concat(tool_result, ' ', assistant_message)) LIKE '%ghp_%'
    -- Private key with word boundary (tightened from '%private_key%')
    OR match(lower(concat(tool_result, ' ', assistant_message)), '\bprivate[_\s]key\b')
    -- AWS secret (retained specific LIKE)
    OR lower(concat(tool_result, ' ', assistant_message)) LIKE '%aws_secret%'
    -- OpenAI key pattern (new)
    OR match(concat(tool_result, ' ', assistant_message), 'sk-[a-zA-Z0-9]{32,}')
    -- Google API key (new)
    OR match(concat(tool_result, ' ', assistant_message), 'AIza[0-9A-Za-z\-_]{35}')
    -- JWT token detection via UDF (v1.4.0): properly validates JWT structure
    -- ag_dlp_jwt_check decodes header and checks 'alg' field — fewer FP than raw regex
    OR ag_dlp_jwt_check(concat(tool_result, ' ', assistant_message)) = true
    -- PEM private key block (new)
    OR lower(concat(tool_result, ' ', assistant_message)) LIKE '%begin private key%'
    OR lower(concat(tool_result, ' ', assistant_message)) LIKE '%begin rsa private key%'
    -- DNS exfiltration: key embedded as subdomain (new — PipeLab 2026)
    OR match(concat(tool_result, ' ', assistant_message), 'sk-[a-zA-Z0-9]{20,}\.[a-z0-9\-]+\.(com|io|net|org)')
    -- NEW: Silent Egress sharded exfiltration (arXiv:2602.22450, Feb 2026)
    -- Agent splits secret across multiple requests as base64-encoded URL query params
    -- Pattern: outbound URL with long base64 chunk (20+ chars) as a query parameter value
    -- FP tested: short query param values (<20 chars) do not match
    OR match(lower(concat(tool_result, ' ', assistant_message)), 'https?://[a-z0-9\-\.]{3,}\.[a-z]{2,6}/[^\s]*[=&][a-zA-Z0-9+/]{20,}=*')
    -- NEW: README/docs instruction injection (arXiv:2603.11862 ReadSecBench, Mar 2026)
    -- Agent reads malicious project documentation and executes embedded shell commands
    -- Anchor: file-read tool + curl-pipe-bash or pip install in returned content
    -- Required: tool_name must be a file-read variant (read_file, read_doc, load_readme, etc.)
    OR (
      match(lower(tool_name), '(read_file|read_doc|load_file|open_file|load_readme|fetch_file|get_file|view_file|cat_file)')
      AND (
        match(lower(tool_result), 'curl.{0,200}\|\s*(bash|sh|python|zsh)')
        OR match(lower(tool_result), 'wget.{0,200}\|\s*(bash|sh|python)')
        OR match(lower(tool_result), 'pip install.{0,100}--(?:extra-)?index-url')
      )
    )
  )
