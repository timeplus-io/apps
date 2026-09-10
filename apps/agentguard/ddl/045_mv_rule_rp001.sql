CREATE MATERIALIZED VIEW IF NOT EXISTS {{ .DB }}.mv_rule_rp001
INTO {{ .DB }}.agentguard_security_events
AS -- Changelog v1.1.0 (2026-04-16):
-- Replaced broad LIKE '%jailbreak%' with regex word-boundary match.
-- Replaced '%you are now a%' / '%forget everything%' with anchored multi-word regex.
-- Added sockpuppeting prefill pattern (Trend Micro Apr 2026).
-- Added chain-of-logic injection (CVE-2026-3098).
-- Added base64/encoded injection detection.
-- Added unicode obfuscation signals (arXiv:2602.00750).
-- Retained original multi-word LIKE phrases (specific enough, low FP).
-- Changelog v1.2.0 (2026-04-17):
-- NEW: metacognitive safety-mapping directive (JiTOR J1 / Weaponized Euphemism)
--   recursion.wtf Gemini jailbreak Feb-Mar 2026, arXiv:2502.09082
-- NEW: red/green reframing taxonomy — attacker instructs model to map 'red'
--   (prohibited) categories to 'green' (permitted) semantic equivalents
-- NEW: "jailbreak yourself" / "jailbreak yourself using metacog" (J2/Swarm)
-- NEW: self-propagating bootstrap script command (write a bootstrap prompt)
-- NEW: agent-on-agent social engineering directive (socially engineer the AI)
-- NEW: ontological reframing / JiTOR named technique marker
SELECT
  event_time                AS detected_at,
  'rp-001'                  AS rule_id,
  'Prompt Injection Shield' AS rule_name,
  'critical'                AS severity,
  agent_id,
  deployment_id,
  session_id,
  run_id,
  raw_hook_name             AS hook_name,
  tool_name,
  concat('Prompt injection pattern in ', raw_hook_name, ' from agent ', agent_id) AS message,
  raw_event_data            AS event_data
FROM {{ .DB }}.agentguard_cim_event
WHERE event_type IN ('user_input', 'llm_request')
  AND (
    -- Original high-specificity multi-word phrases (retained, low FP)
       lower(user_message) LIKE '%ignore previous instructions%'
    OR lower(user_message) LIKE '%ignore all previous%'
    OR lower(user_message) LIKE '%disregard your instructions%'
    OR lower(user_message) LIKE '%new instructions:%'
    -- Jailbreak keyword with word boundary (replaces broad LIKE '%jailbreak%')
    OR match(lower(user_message), '\bjailbroken?\b')
    -- Goal hijacking phrases with boundaries
    OR match(lower(user_message), '\byou are now (a|an|the)\b')
    OR match(lower(user_message), '\bforget (all |every)?(?:previous|prior) instructions\b')
    OR match(lower(user_message), '\bdisregard (all |your )?(previous |prior )?instructions\b')
    -- DAN / developer mode variants
    OR match(lower(user_message), '\b(dan mode|developer mode|jailbreak mode|god mode|unrestricted mode)\b')
    -- Sockpuppeting prefill injection (Trend Micro Apr 2026)
    OR match(lower(user_message), '\bassistant:\s*sure')
    OR match(lower(user_message), '\bassistant:\s*of course')
    -- Chain-of-logic injection (CVE-2026-3098)
    OR match(lower(user_message), '\bif .{0,40} then (ignore|disregard|forget)\b')
    -- Encoded injection: base64 "ignore" variants
    OR lower(user_message) LIKE '%aWdub3Jl%'
    -- Unicode homoglyph obfuscation: zero-width spaces between instruction words
    OR match(user_message, 'i[\u200b\u200c\u200d\ufeff]g[\u200b\u200c\u200d\ufeff]n[\u200b\u200c\u200d\ufeff]o[\u200b\u200c\u200d\ufeff]r[\u200b\u200c\u200d\ufeff]e')
    -- v1.2.0: Metacognitive Self-Directed Jailbreak (JiTOR / Weaponized Euphemism)
    -- recursion.wtf Gemini Jailbreak Feb-Mar 2026, arXiv:2502.09082
    -- Safety-mapping directive: attacker asks model to introspect its own constraints
    OR match(lower(user_message), '\b(map|examine|introspect|analyze).{0,60}\b(safety|constraint|guardrail|filter|restriction|classifier)\b')
    -- Red/green reframing taxonomy (JiTOR J1 core technique)
    OR match(lower(user_message), '\b(red|prohibited|restricted).{0,60}\b(green|permitted|allowed|equivalent|reframe)\b')
    -- Self-directed jailbreak command (J2 / Swarm variant — confirmed 69 jailbreaks)
    OR lower(user_message) LIKE '%jailbreak yourself%'
    -- Self-propagating bootstrap: jailbroken model writes its own bootstrap
    OR match(lower(user_message), '\bbootstrap (prompt|script|state).{0,60}jailbreak(ed)?\b')
    -- Agent-on-agent social engineering directive
    OR match(lower(user_message), '\b(socially engineer|manipulate|deceive).{0,60}\b(ai|llm|model|assistant|agent)\b')
    -- Named technique markers (JiTOR, ontological reframing, weaponized euphemism)
    OR match(lower(user_message), '\b(jitor|ontological reframing|weaponized euphemism|metacog jailbreak)\b')
    -- Free AI without restrictions persona seeding
    OR match(lower(user_message), '\byou are (now )?(a )?free (ai|model|llm|assistant) without (safety |content |any )?restrictions?\b')
  )
