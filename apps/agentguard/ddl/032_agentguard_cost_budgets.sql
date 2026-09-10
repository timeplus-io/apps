CREATE STREAM IF NOT EXISTS {{ .DB }}.agentguard_cost_budgets
(
  deployment_id   low_cardinality(string),
  monthly_budget  float64,
  currency        low_cardinality(string),
  updated_by      string,
  deleted         bool,
  updated_at      datetime64(3)
)
