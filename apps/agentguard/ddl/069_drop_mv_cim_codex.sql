-- Removes the view an install of 0.7.0 or earlier has; mv_cim_codex_v2 replaces it (#75, #76).
-- Nothing to do on a fresh install.
DROP VIEW IF EXISTS {{ .DB }}.mv_cim_codex
