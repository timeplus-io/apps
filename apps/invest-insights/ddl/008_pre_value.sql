CREATE MUTABLE STREAM IF NOT EXISTS {{ .DB }}.pre_value
(
    SecurityAccount string,
    SecurityId      string,
    prevalue        float64
)
PRIMARY KEY (SecurityAccount, SecurityId);
