insert into {{ .DB }}.pre_value (SecurityAccount, SecurityId, prevalue)
select a.SecurityAccount, a.SecurityId, sum(b.LastPx * a.HoldingQty) as prevalue
from table({{ .DB }}.position) as a
join table({{ .DB }}.stock) as b
on a.SecurityId = b.SecurityID
group by SecurityAccount, SecurityId;
