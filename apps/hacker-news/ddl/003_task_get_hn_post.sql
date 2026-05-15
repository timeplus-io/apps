CREATE TASK IF NOT EXISTS {{ .DB }}.get_hn_post
SCHEDULE {{ .Config.task_schedule }}
TIMEOUT {{ .Config.task_timeout }}
INTO {{ .DB }}.hn_post
AS
  WITH max_post_id AS
  (
    SELECT
      max(to_int64_or_zero(message:id)) AS max_id
    FROM
      table({{ .DB }}.hn_post)
  ), hn_new_posts AS
  (
    SELECT
      get_hn_posts_after_id_with_retry(max_id, {{ .Config.lookback }}, {{ .Config.fetch_limit }}) AS posts,
      array_join(posts) AS joined_post
    FROM
      max_post_id
  )
SELECT
  joined_post AS message
FROM
  hn_new_posts;
