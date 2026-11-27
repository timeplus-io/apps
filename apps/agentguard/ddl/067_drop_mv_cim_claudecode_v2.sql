-- Removes the view an install of 0.7.0 has; mv_cim_claudecode_v3 replaces it (#75, #76).
-- Nothing to do on a fresh install.
DROP VIEW IF EXISTS {{ .DB }}.mv_cim_claudecode_v2
