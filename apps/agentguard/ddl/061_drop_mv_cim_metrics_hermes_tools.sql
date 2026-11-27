-- Removes the view an install of 0.6.0 or earlier has; mv_cim_metrics_hermes_tools_v2 replaces it (#72).
-- Nothing to do on a fresh install.
DROP VIEW IF EXISTS {{ .DB }}.mv_cim_metrics_hermes_tools
