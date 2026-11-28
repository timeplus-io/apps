-- Removes the view an install of 0.10.0 or earlier has; the rule views of 0.11.0 replace it (#86).
-- Nothing to do on a fresh install.
DROP VIEW IF EXISTS {{ .DB }}.mv_rule_rp001
