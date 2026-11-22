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
| Sub-agent robot | `agentguard_cim_event`, `session_start` from `subagent_spawning` | `agent_id`, `agent_type` in `raw_event_data` |
| Phone, outgoing (reply, question), progress update | `agentguard_cim_event`, `llm_response` | `assistant_message` |
| Question through an ask-the-user tool | `agentguard_cim_event`, `tool_invoke` / `tool_complete` of `AskUserQuestion` and similar | `tool_input` (`questions[0].question` or `question`) |
| Failed and denied calls, sub-agent stop, turn ended by an API error | `agentguard_hook_events` | `tool_call_failure`, `permission_denied`, `subagent_ended`, `stop_failure` |
| Instruction files loaded into context (no tool call) | `agentguard_hook_events` | `instructions_loaded`: `file_path`, `memory_type`, `load_reason` |
| Compaction | `agentguard_hook_events`, `agentguard_cim_event` | `pre_compact` (start), `session_start` with `source = compact` or `post_compact` (done) |
| Task list on the board | `agentguard_hook_events` | `task_created`, `task_completed` |
| Skill names and use counts | `agentguard_skills` | `skill_name`, `skill_action`, `skill_source_type` |
| Memory operations | `agentguard_memory_ops` | `memory_op`, `memory_source`, `server_name`, `memory_path` |
| Context gauge and history | `agentguard_cim_metrics` | `llm.input_tokens` + `llm.cache_read_tokens` + `llm.cache_write_tokens` per LLM call |

Tool families map to objects: Bash → Terminal; Read/Write/Edit/Grep/Glob → Local file; WebFetch/WebSearch → Search; Skill → Skill; memory tools and memory files → Memory; `mcp__*` → MCP; Agent/Task → sub-agent; anything else → Other tools. OpenClaw and Hermes tool names are mapped the same way (`web/agent-rooms/src/mapping.js`).

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
- **Per-card token cost** is estimated from payload size (about 4 characters per token) and marked `≈`. The context gauge uses real token metrics, and needs Claude Code telemetry (`CLAUDE_CODE_ENABLE_TELEMETRY=1`) pointed at the app's OTel input; without it the gauge falls back to the estimate.
- **Context limit** is not reported. The gauge assumes 200k, and switches to 1M once a session exceeds 200k.
- **Compaction** is a real event for Claude Code (the session restarts with `source = compact`). For agents that report nothing, it is inferred from a drop of more than 40% (and 20k tokens) in context size. The summary card's size is filled in by the next LLM call.
- **Token metrics do not say which agent made the call.** Calls by a different model or made while a sub-agent is running are left out of the context size.
- **Memory loaded without a tool call**: `CLAUDE.md` and rules files are shown once the Claude Code plugin forwards `InstructionsLoaded` (AgentGuard#305). The auto-memory `MEMORY.md` injected at session start fires no hook and stays invisible; so does the size of any loaded file.
- **Instruction loads, compaction start, the task list and API-error turn ends** need the hooks added in AgentGuard#305. With an older plugin those parts simply stay empty.
- **Skill and memory rows carry no result.** They are matched to their tool call by timestamp; success or failure comes from the call.
- **Tool failures, permission denials and sub-agent stop** are only in `agentguard_hook_events`; the CIM views drop them.

OpenClaw and Hermes sessions are drawn from the same streams but have only been checked with Claude Code so far.

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
```

## Uninstall

Uninstalling drops database `ag` and **all telemetry stored in it**, and removes the Agent Rooms page.
