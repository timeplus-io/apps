CREATE VIEW IF NOT EXISTS {{ .DB }}.profit_v AS
SELECT
    sum_if(px * qty, side = '1')  AS buy_amount,
    sum_if(px * qty, side = '2')  AS sell_amount,
    sum(fee)                       AS deal_fee,
    latest(HoldingQty * f.LastPx) AS cur_value,
    latest(pre_value)              AS pre_value,
    latest(event_ts)               AS event_ts,
    (cur_value + sell_amount - buy_amount - deal_fee - pre_value) AS profit,
    now64(3)                       AS ts,
    SecurityId,
    SecurityAccount
FROM (
    SELECT
        e.event_ts,
        e.px,
        e.qty,
        e.fee,
        e.side,
        e.SecurityId,
        e.SecurityAccount,
        e.pre_value,
        d.HoldingQty
    FROM (
        SELECT
            a.event_ts,
            a.LastPx         AS px,
            a.LastQty        AS qty,
            a.Fee            AS fee,
            a.EntrustDirection AS side,
            a.SecurityId,
            a.SecurityAccount,
            b.prevalue       AS pre_value
        FROM {{ .DB }}.execution AS a
        JOIN table({{ .DB }}.pre_value) AS b
            ON a.SecurityId = b.SecurityId AND a.SecurityAccount = b.SecurityAccount
    ) AS e
    JOIN {{ .DB }}.position AS d
        ON e.SecurityId = d.SecurityId AND e.SecurityAccount = d.SecurityAccount
) AS joined
JOIN {{ .DB }}.stock AS f ON joined.SecurityId = f.SecurityID
GROUP BY SecurityId, SecurityAccount
EMIT PERIODIC 2s;
