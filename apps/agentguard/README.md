# AgentGuard — core telemetry pipeline for AI coding agents

Installs the [AgentGuard](https://github.com/timeplus-io/AgentGuard) streaming pipeline that turns raw telemetry from AI coding agents (Claude Code, Codex, OpenClaw, Hermes, any OpenInference/OTLP emitter) into a normalized event model, per-call metrics, and security detections — all as Timeplus streams and materialized views in database `ag`.

> The SQL in `ddl/` was first generated from the AgentGuard backend. That generator is gone (last in AgentGuard tag `v0.9.3`), so this directory is now the source. An upgrade re-runs every file with `IF NOT EXISTS`, which leaves an installed view as it is: change behaviour by adding a view, not by editing one. To replace a view, add it under a new name (`_v2`), take the old file out of the manifest, and drop the old view with a `type: system` resource (`DROP VIEW IF EXISTS`), as 0.6.1 does.

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
| Dashboards | Eight dashboards: overview, sessions and activity, token usage, tool calls, session trace, threats, usage by agent, latency and errors (see below) |
| Custom UI | Agent Rooms 3D, a live 3D view of agent sessions (see below) |

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
- **Codex**: the [AgentGuard Codex plugin](https://github.com/timeplus-io/AgentGuard/tree/main/agents/codex/agentguard-plugin) has two export paths; use one per deployment (see [Codex](#codex)). By default (0.2.0 or later) it sends one span per Codex hook over OTLP/HTTP to the same port, with the service name `codex`. With `AGENTGUARD_CODEX_EXPORT=hooks` (0.3.0 or later) it writes one row per hook to `ag.agentguard_hook_events`, like the hook plugins below.
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

## Upgrading to 0.6.1

0.6.1 fixes the tool metric views ([#72](https://github.com/timeplus-io/apps/issues/72)). Up to 0.6.0, `mv_cim_metrics_claudecode_tools`, `mv_cim_metrics_openclaw_tools` and `mv_cim_metrics_hermes_tools` each counted the tool calls of every agent under their own agent type, so with more than one agent type reporting, `tool.call`, `tool.success` and `tool.duration_ms` in `agentguard_cim_metrics` were too high.

- The upgrade drops those three views and `mv_cim_metrics_hermes_llm` (same mistake, but it did not over-count) and creates `..._v2` views in their place.
- The new views read from the upgrade on. **Rows written before the upgrade stay as they are**, so tool counts per agent type are still too high for the time before it. For that period, count `tool_complete` rows in `agentguard_cim_event` instead.
- Codex tool metrics (`mv_cim_metrics_codex_tools`) were not affected.

## Dashboards

Eight dashboards, each on one question and with at most six charts. All but Session Trace have a **Time range** and a **Deployment** control (the deployments seen in the last 30 days, or `all`), and all but Threats and Session Trace also filter by **Agent type**. Session Trace has a **Session** list and a **Turn** list instead.

| Dashboard | File | Shows |
|---|---|---|
| Agents: Overview | `dashboards/main.json` | Active sessions, tool calls, tokens and open threats as numbers; events over time; the most active sessions |
| Agents: Sessions and Activity | `dashboards/sessions.json` | Active sessions over time, activity mix (prompts, model requests, tool calls, replies), sessions by project, session profile per agent type, time waiting on a person, the session list |
| Agents: Token Usage | `dashboards/tokens.json` | Tokens by model and by type, cache hit ratio, model request latency (p95), usage per model, the sessions using the most tokens |
| Agents: Tool Calls | `dashboards/tools.json` | Tool calls over time, top tools, tool duration (p95), failed and blocked calls, MCP servers and skills, repeated calls |
| Agents: Session Trace | `dashboards/session_trace.json` | One session as a trace: a two-line summary (project, agent, model, state, times, counts and tokens), a waterfall of its turns, a waterfall of the steps of one turn (prompt, model requests, tool calls, waits on a person, reply), context growth, time by tool, detections. Pick the session in **Session**, at the top, and the turn in **Turn**, right above the steps; both default to `latest` |
| Agents: Threats | `dashboards/threats.json` | Open threats by severity, detections over time by rule, by rule and tool, by session, blocked actions, recent threats |
| Agents: Usage by Agent | `dashboards/agents.json` | Sessions and tokens over time per agent, tokens by agent and model, tool calls by agent (worked and failed), usage per agent and per deployment |
| Agents: Latency and Errors | `dashboards/latency.json` | Model request latency p50/p95/p99 over time and its distribution, turn duration by agent type, model request errors and retries, the slowest requests, reliability by agent type |

Where the data comes from: sessions, steps, tool calls and waits on a person from `agentguard_cim_event`; tokens and latency from `agentguard_cim_metrics`; threats from `agentguard_security_events` and `agentguard_threats`; skills from `agentguard_skills`.

What to expect:

- **Claude Code tokens need the Claude Code plugin 0.7.1 or later** (or Claude Code's own telemetry, `CLAUDE_CODE_ENABLE_TELEMETRY=1`, pointed at the app's OTel input). The plugin sends one row per model request when a turn ends, so the tokens of a turn appear at its end. Use one of the two: a session that reports on both is counted twice. "Model requests" in the Activity mix stays a Codex figure; for Claude Code the count is on Session Trace.
- **Failed tool calls**: for Claude Code, every call the agent reports as failed (a non-zero exit, a tool error). For Codex, MCP calls that return an error; a Codex shell call counts as a success whatever its exit status, as the hook does not give it. Failures are recorded from the upgrade to 0.8.0 on.
- **Tool duration for Claude Code** is there for calls made after the upgrade to 0.7.0.
- A Claude Code turn is its `prompt_id`. The plugin sends it as `run_id` from 0.7.0; for older rows the dashboards read it from the payload.
- **Session Trace**:
  - *Session* lists the 50 most recently active sessions, newest first, as last event, agent, project and id. *Turn* lists the turns of that session as start time, first words of the prompt, tool calls and id. Type in a list to search it.
  - *Turns* draws one bar per turn along the time of the session (the latest 50). *Steps of the turn* draws one row per step, in order, on the time of the turn: a tool call and a model request from start to end, a prompt, a reply and a wait as a mark. A failed tool call has its own colour.
  - Point at a bar for the details: duration, the tool input and result (or error), the model and token counts of a model request, the prompt or reply text.
  - A tool call starts at its end less its duration, a model request at its end less its latency. Model requests are drawn when the turn has token metrics: Codex, and Claude Code with the plugin 0.7.1 or later, where they arrive when the turn ends.
  - A panel has a fixed height: it cannot grow or shrink with the number of steps, and a chart cannot scroll inside it. The steps panel has the height of the turns panel, which suits the usual turn of up to about 25 steps; a longer turn is drawn denser, with fewer labels, up to its first 200 steps. In edit mode the panel can be dragged taller. The steps of a sub-agent are grouped under a bar for the sub-agent, right after the call that started it, and marked with └; the chart has flat rows, so this is grouping, not a tree. A Claude Code sub-agent's model requests are drawn when the plugin sent them (on SubagentStop).
- **Usage by Agent**: an agent is one `agent_id`, the machine or account a plugin reports as; a deployment groups agents. With one machine reporting there is one row.
- **Model request errors and retries** are read from the raw hook events: a Codex model request that did not complete or was attempted again, and a Claude Code turn that an API error ended (`stop_failure`). For Claude Code there is no row for a model request that is retried inside a turn, so its retries are not counted.
- Charts over time use up to 60 bars, at least a minute wide, so the bar width follows the time range. Tables that rank show the top eight; tables that list show the newest 100 rows with the latest at the bottom.

Editing a dashboard: a column or bar chart with a series (`color`) must update by a key that is unique per row (`updateMode: "key"`, with `updateKey` naming a column made of x and series together), or it draws one series per bar and looks unstacked; the console's table shows the last `rowCount` rows of a result and opens at its last row, the controls of a row must fill it (a panel beside a narrower control row is lifted into it; a control can sit lower than the first row, as Turn does right above the steps panel it drives), and every control needs a default value. A selector takes its options from the first column of the query in its `viz_content`; the chosen text is put into the panel queries as it is, so the Session and Turn lists build each option without quote characters and the queries take the id as its last word. The two waterfalls are `grammar` charts: an interval mark with a start (`y`) and an end (`y1`) on a transposed coordinate, with the tooltip fields named in the spec. `make test` checks these.

## Upgrading to 0.10.0

Only the dashboards change ([#84](https://github.com/timeplus-io/apps/issues/84)).

- Two new dashboards: **Agents: Usage by Agent** and **Agents: Latency and Errors**.
- A **Deployment** filter on every dashboard that has a Time range.
- Session Trace groups the steps of a sub-agent under a bar for the sub-agent.

## Upgrading to 0.9.0

0.9.0 turns Agents: Session Trace into a trace view. Only that dashboard changes.

- The Session ID text box is a **Session** list of the 50 most recently active sessions, and a **Turn** list, right above the steps, picks a turn of that session.
- The Turns and Steps tables are **waterfall charts**: one bar per turn on the time of the session, and one row per step of the picked turn, with the details in the tooltip.
- The session summary is two lines of text instead of a one-row table.

## Upgrading to 0.8.1

0.8.1 fixes the charts with more than one series per bar. In 0.7.0 and 0.8.0 the stacked charts drew one series for each bar and dropped the others, so a bar showed, for example, only the replies of a period and not its tool calls and prompts. Affected: Events over time (Overview); Active sessions over time, Activity mix, Sessions by project, Waiting on a person (Sessions and Activity); Tokens by model, Tokens by type (Token Usage); Tool calls over time, Top tools, Failed and blocked tool calls (Tool Calls); Detections over time by rule (Threats). The numbers and tables on the same dashboards were right. Only the dashboards change in this version.

## Upgrading to 0.8.0

0.8.0 records failed tool calls ([#75](https://github.com/timeplus-io/apps/issues/75)), puts permission requests and notifications in the CIM stream ([#76](https://github.com/timeplus-io/apps/issues/76)), and reads the per-request token rows of the Claude Code plugin 0.7.1.

- `mv_cim_claudecode_v2` is dropped and `mv_cim_claudecode_v3` created. A `tool_call_failure` hook row becomes a `tool_complete` row with `tool_success = false` and the error as `tool_result`; before, a failed call had no `tool_complete` row. `permission_request`, `permission_denied` and `notification` hook rows become CIM rows with that `event_type`.
- `mv_cim_codex` is dropped and `mv_cim_codex_v2` created. `tool_success` is false for an MCP response with `isError: true`, and `permission_request` becomes a CIM row.
- `mv_cim_metrics_claudecode_llm` is new: `llm.*` metrics from the plugin's `llm_call` rows, including the ones already stored.
- The new CIM views read from the upgrade on. Events that arrive in the moment between a drop and its create are not turned into CIM rows.
- **New `event_type` values** in `agentguard_cim_event`: `permission_request`, `permission_denied`, `notification`. A query that counts all rows of a session now counts these too. The four rules and Agent Rooms name the event types they read and are not affected.
- `tool.call` now counts failed Claude Code calls, and `tool.success` is 0 for them.

## Upgrading to 0.7.0

- The single dashboard, AgentGuard Overview, is replaced by the six above. Their names start with "Agents:".
- `mv_cim_claudecode` is dropped and `mv_cim_claudecode_v2` created in its place: the same view, with `tool_duration_ms` read from the tool call's `duration_ms`. It reads from the upgrade on; Claude Code events that arrive in the moment between the drop and the create are not turned into CIM rows.

## Agent Rooms 3D

A live 3D view of the agent sessions AgentGuard is collecting, shipped in the package as a custom UI. Each session is a room. A robot walks between labelled objects to show what the agent is doing right now: taking a user instruction, reading files, running commands, loading skills, delegating to sub-agents, and filling its context window. The side panel shows session status and the history of any object you click.

Open it in the console: **Apps → AgentGuard → Custom UI → Agent Rooms 3D**. The page is optional: it is available on Timeplus app server 3.5.2 or later. Older versions have no custom UI support; there the app installs and works as before, without the page.

There is nothing to configure. The console tells the page the workspace, the app's database, the theme and the language, and the page's queries run with your console session, so what you can see is what your user may read. The settings are **Look back** (15 minutes to 24 hours): how far back sessions are loaded from, and the visual style (below). Both are remembered per browser.

The page has two visual styles, chosen with the **Studio / Sketchbook** switch in its header:

- **Studio**: solid rooms under a perspective camera, with a caption bar saying what the agent is doing.
- **Sketchbook**: an isometric drawing on paper, with ink outlines and handwritten labels. The stage carries the session name, the time since the session started, the current step, and the trail of the last five things the agent did. Hovering an object shows a callout with its name and its latest event.

Picking a session shows its room alone, in both styles; **All rooms** brings the others back.

#### The conversation with the user

The phone is the two-way line to the user, and its sign shows the direction: one face while the user is talking, a lighter one while the agent is.

| What happened | What the room shows | How it is recognised |
|---|---|---|
| The user sends an instruction | The phone rings; the agent answers and carries the prompt card to the bench (↓ in the history) | `user_input` |
| The agent replies | It writes a reply card at the bench, carries it to the phone and speaks, word by word (↑) | An assistant message at the end of a turn |
| The agent asks the user something | It calls out the same way, then holds the line: **Waiting on user**, shown in the room title in the All rooms view too. When the answer comes it carries the answer card to the bench | A turn-ending message whose last line ends in a question mark, or a call to an ask-the-user tool (`AskUserQuestion`, `ask_user`, `ask_followup_question`, `clarify`). It lasts until the next user message, or until the tool returns |
| A progress update | A short bubble at the bench, no walk to the phone (`·` in the trail) | An assistant message that is followed by more tool calls in the same turn |

The side panel shows the **Latest response** under the latest user prompt ("Asked: …" for a question). A reply card is sized from the length of the message, like other cards before token metrics arrive.

Two limits of this mapping: a reply that ends with a rhetorical question is shown as waiting on the user, and a message is only known to be a progress update once the next tool call arrives, so one the robot has already carried to the phone stays in the history as a reply.

Each style has a light and a dark mode. There is no light/dark switch on the page: the mode is the console's theme, including a change made while the page is open (Timeplus Web 3.5.4 or later), and the 3D stage follows it too. The page's text is English in every console language.

### Where the data comes from

Nothing is scripted or mocked. The page runs five streaming queries through the Timeplus REST API (`POST /{workspace}/api/v1beta2/queries`) as the signed-in user and keeps them open. Rows inside the look-back window build the current state; rows that arrive afterwards are animated.

| On screen | Stream | Columns |
|---|---|---|
| Rooms, agent badge, model | `agentguard_cim_event` | `session_id`, `agent_type`, `agent_id`, `model`, `cwd` from `raw_event_data` |
| Phone, incoming (user instruction or answer), board (task) | `agentguard_cim_event`, `user_input` | `user_message` |
| Trips to an object, result cards | `agentguard_cim_event`, `tool_invoke` / `tool_complete` | `tool_name`, `tool_input`, `tool_result` size, `tool_success`, `tool_use_id` |
| Sub-agent robot | `agentguard_cim_event`, `session_start` from `subagent_spawning` (Codex: `subagent_start`) | `agent_id`, `agent_type` in `raw_event_data` (Codex on the OTel path: `agentguard.subagent.id`, `agentguard.subagent.type`) |
| Phone, outgoing (reply, question), progress update | `agentguard_cim_event`, `llm_response` | `assistant_message` |
| Question through an ask-the-user tool | `agentguard_cim_event`, `tool_invoke` / `tool_complete` of `AskUserQuestion` and similar | `tool_input` (`questions[0].question` or `question`) |
| Failed and denied calls, sub-agent stop, turn ended by an API error | `agentguard_hook_events` | `tool_call_failure`, `permission_denied`, `subagent_ended`, `stop_failure` |
| Interrupted turn, permission request (Codex; in the activity log) | `agentguard_hook_events` | `interrupt`, `permission_request` |
| Instruction files loaded into context (no tool call) | `agentguard_hook_events` | `instructions_loaded`: `file_path`, `memory_type`, `load_reason` |
| Compaction | `agentguard_hook_events`, `agentguard_cim_event` | `pre_compact` (start), `session_start` with `source = compact` or `post_compact` (done) |
| Task list on the board | `agentguard_hook_events`; Codex: `agentguard_cim_event`, `tool_invoke` of `update_plan` | `task_created`, `task_completed`; Codex: `plan` in `tool_input` |
| Skill names and use counts | `agentguard_skills` | `skill_name`, `skill_action`, `skill_source_type` |
| Memory operations | `agentguard_memory_ops` | `memory_op`, `memory_source`, `server_name`, `memory_path` |
| Context gauge and history | `agentguard_cim_metrics` | `llm.input_tokens` + `llm.cache_read_tokens` + `llm.cache_write_tokens` per LLM call |

Tool families map to objects: Bash → Terminal; Read/Write/Edit/Grep/Glob → Local file; WebFetch/WebSearch → Search; Skill → Skill; memory tools and memory files → Memory; `mcp__*` → MCP; Agent/Task → sub-agent; anything else → Other tools. OpenClaw, Hermes and Codex tool names are mapped the same way (`web/agent-rooms/src/mapping.js`).

### Codex

Codex sessions come from the [AgentGuard Codex plugin](https://github.com/timeplus-io/AgentGuard/tree/main/agents/codex/agentguard-plugin), which can send them in two ways. A deployment uses one: the plugin never sends both, and a session sent both ways would be counted twice.

| | OTel path (default) | Hook-event path |
|---|---|---|
| Plugin | 0.2.0 or later | 0.3.0 or later, `AGENTGUARD_CODEX_EXPORT=hooks` |
| App | 0.5.0 or later | 0.6.0 or later |
| What is sent | one OTLP span per Codex hook, service name `codex` | one `agentguard_hook_events` row per Codex hook, `agent_type = 'codex'`, the hook payload in `event_data` |
| Port on the Timeplus host | `otel_port` (4318) | 3218 (timeplusd ingest, the plugin's default) or 8000 (Timeplus REST API, `AGENTGUARD_INGEST_API=rest`) |
| Lands in | `otel_traces` | `agentguard_hook_events` |

The views that serve each path:

| Into | OTel path | Hook-event path |
|---|---|---|
| `agentguard_cim_event` | `mv_cim_openinference` (model requests, tool calls, session), `mv_cim_openinference_hooks` (prompt, reply, session and sub-agent start) | `mv_cim_codex_v2` |
| `agentguard_cim_metrics`, `llm.*` | `mv_cim_metrics_openinference_llm` | `mv_cim_metrics_codex_llm` |
| `agentguard_cim_metrics`, `tool.call` and `tool.success` | `mv_cim_metrics_codex_tools` (both paths) | `mv_cim_metrics_codex_tools` |
| `agentguard_skills` | `mv_skills_invoked_codex` | `mv_skills_invoked_codex_hooks` |
| `agentguard_hook_events` (sub-agent stop, compaction, interrupt, permission request) | `mv_hook_bridge_openinference_hooks`, and `mv_hook_bridge_openinference` for model requests, tool calls and the session | written by the plugin |

On the OTel path the bridge views write rows into `agentguard_hook_events` with `agent_type = 'codex'` too. The plugin marks the rows it writes on the hook-event path with `"agentguard.export": "hooks"` in `event_data`, and the hook-event views read only marked rows, so an OTel-path session is never read twice.

The same session gives the same rows on either path: the same events in `agentguard_cim_event`, the same token counts in `agentguard_cim_metrics`, the same skill rows, and the same room in Agent Rooms. The hook-event path differs in these columns:

- `raw_hook_name` is the hook name (`pre_tool_use`, `post_tool_use`, `session_end`); on the OTel path it is the span name (`tool`, `session`).
- `run_id` is the Codex turn id on every row; on the OTel path it is empty on model request, tool and session rows.
- `tool_invoke` comes from `pre_tool_use`, when the call starts, and has no result yet. On the OTel path both tool rows come from one span sent when the call has finished.
- `tool_input` and `tool_result` are the JSON of the hook payload without spaces after `:` and `,`.
- `tool_duration_ms` is set on `tool_complete` only; `hook_decision` is `observe`.
- There is one `session_start` row per session. On the OTel path the `session` span sent at the end repeats the session's start, so a finished session has two.
- `llm.cache_write_tokens` is written when Codex reports `cache_write_input_tokens`. Metric tags carry `run_id` where the OTel path has `trace_id`.
- `llm.latency_ms`, `tool_duration_ms` and the time of the `llm_request` row need the plugin to have seen the start of the request or call. Without it there is no `llm.latency_ms` row, the duration is 0 and `llm_request` has the time of its `llm_response`.

`mv_cim_metrics_codex_tools` is new in 0.6.0 and reads `agentguard_cim_event`, so from 0.6.0 Codex tool calls are counted on the OTel path too, including the ones already stored when the app is upgraded.

What differs from Claude Code on screen:

- **File reads go through the shell.** Codex has no read, search or list tool. A shell command that starts with `cat`, `sed -n`, `head`, `tail`, `rg`, `grep`, `ls`, `find` and the like, and redirects nothing to a file, is drawn as a trip to Local file; any other command goes to the Terminal. Only the first command of a pipeline or chain is looked at.
- **Skills** have no tool either: reading `<skill>/SKILL.md` through the shell counts as using that skill.
- **File edits** are `apply_patch`; the label is the first file named in the patch.
- **The task list** is the plan from `update_plan`.
- **The context gauge** uses `llm.input_tokens` alone. Codex counts cached tokens inside its input tokens, so `llm.cache_read_tokens` and `llm.cache_write_tokens` are not added.
- **On the OTel path a tool call appears when it has finished.** The plugin sends one span per call, at the end, so the robot makes the trip after the fact and there is no `running` timer. On the hook-event path the call appears when it starts.

Not shown for Codex, because nothing reports it: instruction files (`AGENTS.md`) and the system prompt, the list of available skills, memory, and failed tool calls (a failed command still reports as a completed call).
Sub-agents, compaction, interrupts, permission requests and `update_plan` were checked with replayed hook payloads, not a live Codex session. The hook-event path as a whole was checked the same way: `tests/codex-hooks/hook-rows.json` is one session as the plugin writes it (all 14 hooks, one sub-agent, one compaction), and `make test-codex-hooks` replays it into a Timeplus that has the app installed and checks the rows of the four views and the room Agent Rooms builds from them.

### How behaviour is derived

- **Operating** lasts as long as the real call: the robot stays at the object until `tool_complete` (or a failure hook) arrives. Calls open for 4 seconds or more show a `running m:ss` timer.
- **Thinking** is inferred: a prompt or tool result has arrived and nothing has followed. Claude Code has no "LLM call started" event.
- **Burst**: three or more queued calls to the same object become one trip with a `×N` counter and one thick card.
- **Catching up**: shown when three or more events are waiting; walking and waits run 2.2× faster.
- **Idle**: the turn has ended (`llm_response` or `session_end`), or nothing has happened for two minutes.
- Up to six rooms are shown: the most recently active sessions in the look-back window.

### Known gaps in the data

Checked against real Claude Code sessions:

- **System prompt text** is not reported, so the board shows the task only.
- **Per-card token cost** is estimated from payload size (about 4 characters per token) and marked `≈`. The context gauge uses real token metrics. For Claude Code they come from the plugin 0.7.1 or later, at the end of each turn, or from Claude Code telemetry (`CLAUDE_CODE_ENABLE_TELEMETRY=1`) pointed at the app's OTel input; without either the gauge falls back to the estimate.
- **Context limit** is not reported. The gauge assumes 200k, and switches to 1M once a session exceeds 200k.
- **Compaction** is a real event for Claude Code (the session restarts with `source = compact`). For agents that report nothing, it is inferred from a drop of more than 40% (and 20k tokens) in context size. The summary card's size is filled in by the next LLM call.
- **Token metrics do not say which agent made the call.** Calls by a different model or made while a sub-agent is running are left out of the context size.
- **Memory loaded without a tool call**: `CLAUDE.md` and rules files are shown once the Claude Code plugin forwards `InstructionsLoaded` (AgentGuard#305). The auto-memory `MEMORY.md` injected at session start fires no hook and stays invisible; so does the size of any loaded file.
- **Instruction loads, compaction start, the task list and API-error turn ends** need the hooks added in AgentGuard#305. With an older plugin those parts simply stay empty.
- **Skill and memory rows carry no result.** They are matched to their tool call by timestamp; success or failure comes from the call.
- **Tool failures, permission denials and sub-agent stop** are only in `agentguard_hook_events`; the CIM views drop them.

OpenClaw and Hermes sessions are drawn from the same streams but have not been checked with a live session.

### Files

`web/agent-rooms/` is the bundle: everything in it is installed and served. Tests live in `tests/agent-rooms/` and are not packaged.

| File | Purpose |
|---|---|
| `index.html` | Page shell and styles |
| `vendor/tp-context.js` | Workspace, database, theme and locale from the console: entry URL, then live `timeplus:context` messages. A copy of `skill/assets/tp-context.js`; `make vendor-context` refreshes it |
| `src/context.js` | The look-back setting |
| `src/looks.js` | The four looks (Studio and Sketchbook, light and dark): scene colours, lights, sign colours; `index.html` has the matching CSS variables |
| `src/queries.js` | The five SQL queries |
| `src/timeplus.js`, `src/sse.js` | Query client (session cookie, no credentials) and stream parsing |
| `src/store.js` | Rows → per-session state and the queue of things to act out |
| `src/mapping.js` | Tool → object mapping, labels |
| `src/scene.js`, `src/icons.js` | three.js rooms, robot, animation |
| `src/panel.js`, `src/main.js` | Side panel and wiring |
| `vendor/` | three.js 0.184.0 (MIT), shipped in the bundle; `make vendor` refreshes it |
| `vendor/fonts/` | Inter (one variable file for all weights), and Fraunces 600 and Patrick Hand 400 for the Sketchbook style. Latin and latin-ext subsets, SIL OFL, license in `OFL.txt`. The page cannot use the console's fonts, so every font it names is shipped |

```bash
make test     # unit tests for the page logic (Node 20+)
make build    # zips the bundle into the package and checks it (entry file, size limits, file names)

# live check of the Codex hook-event path against an installed app (timeplusd SQL port)
TIMEPLUS_URL=http://localhost:8123 TIMEPLUS_USER=... TIMEPLUS_PASSWORD=... make test-codex-hooks
```

## Uninstall

Uninstalling drops database `ag` and **all telemetry stored in it**, and removes the Agent Rooms page.
