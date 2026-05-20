CREATE VIEW IF NOT EXISTS {{ .DB }}.v_resource_cost_now AS
SELECT * FROM {{ .DB }}.aws_resource_cost_live;
