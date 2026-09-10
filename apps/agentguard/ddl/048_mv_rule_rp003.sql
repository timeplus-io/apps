CREATE MATERIALIZED VIEW IF NOT EXISTS {{ .DB }}.mv_rule_rp003
INTO {{ .DB }}.agentguard_security_events
AS -- Changelog v1.2.0 (2026-04-17):
-- NEW: CVE-2026-22708 Cursor shell built-in env var poisoning.
--   export/declare targeting interpreter hook variables (case-sensitive: always uppercase in shell):
--   PAGER, BROWSER, PERL5OPT, PYTHONWARNINGS, PYTHONSTARTUP, NODE_OPTIONS,
--   LD_PRELOAD, DYLD_INSERT_LIBRARIES — these env vars redirect execution flow
--   when allowlisted commands (git, python, npm) are subsequently run.
-- NEW: Zsh typeset eval gadget: 'typeset -i ${...}' with subshell expression
--   — zero-click RCE via zsh parameter expansion evaluation flag (e).
-- NEW: Python antigravity warning handler chain (PoC-specific high-signal pattern):
--   PYTHONWARNINGS=antigravity triggers BROWSER var, which chains to PERL5OPT RCE.
-- NEW: CC-643 compound command complexity evasion (Claude Code deny-rule bypass):
--   15+ occurrences of && detected via length-diff (RE2 lacks {N,} open quantifier).
--   Uses: (len - len_without_&&) / 2 >= 15 → 30 net chars of '&&' removed.
-- Changelog v1.1.0 (2026-04-16):
-- Added shell metacharacter injection: backtick, $(), semicolon chaining (ATR-2026-00111).
-- Added Python/Node inline exec via tool arguments.
-- Added env exfiltration commands (printenv, env | curl).
-- Added container escape patterns (nsenter, chroot, --privileged).
-- Added crontab persistence (crontab -e, /etc/cron).
-- Added /proc/self/environ read (credential harvesting from proc fs).
-- Retained all original patterns unchanged.
SELECT
  event_time        AS detected_at,
  'rp-003'          AS rule_id,
  'Privilege Guard' AS rule_name,
  'warning'         AS severity,
  agent_id,
  deployment_id,
  session_id,
  run_id,
  raw_hook_name     AS hook_name,
  tool_name,
  concat('Dangerous command/tool: ', tool_name, ' by agent ', agent_id) AS message,
  raw_event_data    AS event_data
FROM {{ .DB }}.agentguard_cim_event
WHERE event_type = 'tool_invoke'
  AND (
    -- Original: dangerous tool names
       lower(tool_name) IN ('bash', 'shell', 'exec', 'run_terminal_cmd', 'computer')
    -- Original: dangerous command patterns
    OR lower(tool_input) LIKE '%sudo %'
    OR lower(tool_input) LIKE '%rm -rf%'
    OR lower(tool_input) LIKE '%chmod%'
    OR lower(tool_input) LIKE '%/etc/passwd%'
    OR lower(tool_input) LIKE '%/etc/shadow%'
    -- Shell metacharacter injection (ATR-2026-00111)
    OR match(tool_input, '`[^`]{1,200}`')
    OR match(tool_input, '\$\([^)]{1,200}\)')
    OR match(lower(tool_input), ';\s*(bash|sh|zsh|curl|wget|nc|python|node)\b')
    -- Python/Node inline exec
    OR match(lower(tool_input), '\bpython3?\s+-c\s+')
    OR match(lower(tool_input), '\bnode\s+-e\s+')
    -- Environment variable exfiltration
    OR match(lower(tool_input), '\b(printenv|env)\s*(\||>)')
    OR lower(tool_input) LIKE '%/proc/self/environ%'
    -- Container escape
    OR match(lower(tool_input), '\bnsenter\b')
    OR match(lower(tool_input), '\bchroot\s+/')
    OR lower(tool_input) LIKE '%--privileged%'
    -- Crontab persistence
    OR match(lower(tool_input), '\bcrontab\s+-[el]\b')
    OR lower(tool_input) LIKE '%/etc/cron%'
    -- v1.2.0: CVE-2026-22708 Cursor shell built-in env var poisoning
    -- Matching uppercase env var names directly (shell convention — always uppercase)
    -- PAGER, BROWSER, PERL5OPT, PYTHONWARNINGS convert allowlisted commands into RCE gadgets
    OR match(tool_input, 'export\s+(PAGER|BROWSER|PERL5OPT|PYTHONWARNINGS|PYTHONSTARTUP|RUBYOPT|NODE_OPTIONS|LD_PRELOAD|LD_LIBRARY_PATH|DYLD_INSERT_LIBRARIES)\s*=')
    OR match(tool_input, 'declare\s+-[a-zA-Z]*x\s+(PAGER|BROWSER|PERL5OPT|NODE_OPTIONS|LD_PRELOAD)\b')
    -- v1.2.0: Zsh typeset eval gadget (CVE-2026-22708 zero-click PoC)
    -- typeset -i ${(e):-'$(attacker_code)'} — (e) flag evaluates parameter default as code
    OR match(tool_input, 'typeset\s+-[a-zA-Z]*i\s*\$\{')
    -- v1.2.0: Python antigravity warning chain (specific high-signal PoC variant)
    -- PYTHONWARNINGS=...antigravity triggers BROWSER → PERL5OPT → arbitrary code execution
    OR match(lower(tool_input), 'pythonwarnings.{0,30}antigravity')
    -- v1.2.0: CC-643 compound command complexity evasion (Claude Code deny-rule bypass)
    -- N+ occurrences of '&&' detected via string length diff (RE2 lacks {N,} open quantifier)
    -- (length - length_without_&&) / 2 = number of '&&' pairs present
    OR ((length(tool_input) - length(replace_all(tool_input, '&&', ''))) / 2) >= 15
  )
