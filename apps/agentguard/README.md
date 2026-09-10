# AgentGuard — core telemetry pipeline for AI coding agents

Installs the [AgentGuard](https://github.com/timeplus-io/AgentGuard) streaming pipeline that turns raw telemetry from AI coding agents (Claude Code, OpenClaw, Hermes, any OpenInference/OTLP emitter) into a normalized event model, per-call metrics, and security detections — all as Timeplus streams and materialized views in database `ag`.

> This package is **generated** from the AgentGuard backend (`make tpapp` in the AgentGuard repo). Do not edit the SQL here by hand; change the backend DDL and regenerate.

## What gets installed

| Layer | Resources |
|---|---|
| Raw OTel | `otel_traces`, `otel_logs`, `otel_metrics_*` streams + `agentguard_otel_input` (OTLP/HTTP receiver on `otel_port`) |
| Raw hooks | `agentguard_hook_events` — agent plugins insert here |
| CIM | `agentguard_cim_event` + `mv_cim_*` normalizers (one per agent type) |
| Metrics | `agentguard_cim_metrics` + `mv_cim_metrics_*` (tokens, latency per call), lookup streams `agentguard_session_agents`, `agentguard_run_latency` |
| Security | `agentguard_security_events`, `agentguard_threats` + `mv_threats` |
| Derived | `agentguard_skills` + `mv_skills_*`, `agentguard_memory_ops` + `mv_memory_*` |
| Cost | `agentguard_pricing`, `agentguard_cost_budgets` (schema only) |
| Rules | `agentguard_rules` + four Core Protection detections `mv_rule_rp001..rp004`, running from install |

Not included (they need the AgentGuard server): user management, notifications, approval holds, Sentry, Semantic DLP, and the rest of the rule catalog.

## Build & install

```bash
make build
make install            # NEUTRON_URL=http://localhost:8000 TENANT=default
```

Or from the apps repo root: `make build APP=agentguard`.

## Config

| key | default | notes |
|---|---|---|
| `otel_port` | `4318` | TCP port the OTLP/HTTP input listens on. Pick another port if 4318 is already taken on the Timeplus host. |
| `otel_listen_host` | `0.0.0.0` | Bind address for the OTLP/HTTP input |

## Sending telemetry

- **OTLP/HTTP** (Claude Code with `CLAUDE_CODE_ENABLE_TELEMETRY=1`, OpenInference exporters): point `OTEL_EXPORTER_OTLP_ENDPOINT` at `http://<timeplus-host>:<otel_port>`.
- **Hook plugins** (AgentGuard Claude Code / OpenClaw / Hermes plugins): configure them to write to stream `ag.agentguard_hook_events`.

## Detection rules

The four Core Protection rules run from the moment the app is installed:

| MV | Rule |
|---|---|
| `mv_rule_rp001` | Prompt Injection Shield |
| `mv_rule_rp002` | DLP Sentinel |
| `mv_rule_rp003` | Privilege Guard |
| `mv_rule_rp004` | Supply Chain Watch |

Matches land in `ag.agentguard_security_events`; `mv_threats` folds them into `ag.agentguard_threats` (one row per agent/session/rule). To switch a rule off or back on:

```sql
SYSTEM PAUSE MATERIALIZED VIEW ag.mv_rule_rp002;
SYSTEM RESUME MATERIALIZED VIEW ag.mv_rule_rp002;
```

(The package deliberately does not pause rules at install time: a `SYSTEM PAUSE` issued right after a distributed `CREATE` fails on multi-node clusters, and re-running it on upgrade would re-pause rules you had enabled.)

## Attaching the AgentGuard UI

Set `timeplus.database: ag` in AgentGuard's `config.yaml` (or `TIMEPLUS_DATABASE=ag`). The setup wizard then reports every resource as already present and the UI reads the app's streams.

## Dashboard

`dashboards/main.json` — AgentGuard Overview: events per minute by agent type, tokens by model, open threats by severity, recent threats.

## Uninstall

Uninstalling drops database `ag` and **all telemetry stored in it**.
