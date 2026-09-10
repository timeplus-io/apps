CREATE MATERIALIZED VIEW IF NOT EXISTS {{ .DB }}.mv_cim_metrics_claudecode_otel
INTO {{ .DB }}.agentguard_cim_metrics AS
SELECT
  o._tp_time                                                              AS event_time,
  metric_name,
  metric_value,
  'claudecode'                                                            AS agent_type,
  if(s.agent_id != '', s.agent_id, o.log_attributes['user.id'])          AS agent_id,
  s.deployment_id                                                         AS deployment_id,
  o.log_attributes['session.id']                                         AS session_id,
  map_cast(
    ['model', 'provider', 'run_id'],
    [
      o.log_attributes['model'],
      multi_if(
        position(o.log_attributes['model'], '@') > 0, 'vertex',
        match(o.log_attributes['model'], '^(us\\.|eu\\.|ap\\.)?anthropic\\.'), 'bedrock',
        'anthropic'
      ),
      o.log_attributes['session.id']
    ]
  )                                                                       AS tags
FROM {{ .DB }}.otel_logs AS o
LEFT JOIN {{ .DB }}.agentguard_session_agents AS s
  ON s.session_id = o.log_attributes['session.id']
ARRAY JOIN
  ['llm.call', 'llm.input_tokens', 'llm.output_tokens', 'llm.total_tokens',
   'llm.cache_read_tokens', 'llm.cache_write_tokens', 'llm.latency_ms']  AS metric_name,
  [
    to_float64(1),
    to_float64_or_zero(o.log_attributes['input_tokens']),
    to_float64_or_zero(o.log_attributes['output_tokens']),
    to_float64_or_zero(o.log_attributes['input_tokens'])
      + to_float64_or_zero(o.log_attributes['output_tokens']),
    to_float64_or_zero(o.log_attributes['cache_read_tokens']),
    to_float64_or_zero(o.log_attributes['cache_creation_tokens']),
    to_float64_or_zero(o.log_attributes['duration_ms'])
  ]                                                                       AS metric_value
WHERE o.log_attributes['event.name'] = 'api_request'
