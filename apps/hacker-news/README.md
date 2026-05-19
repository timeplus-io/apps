# Hacker News Live Feed

Continuously ingests Hacker News posts and comments via the official Firebase API into a Timeplus stream, ready for real-time analysis of trending stories, active users, and post-type distributions.

## How it works

A scheduled task polls the HN Firebase API every `task_schedule` seconds, fetching up to `fetch_limit` new items per run, and inserts them into the `hn_post` stream. No external dependencies beyond the public HN API.

## Build & install

```bash
make build
make install
```

Or from the repo root: `make build APP=hacker-news`.

## Config

| key | default | notes |
|---|---|---|
| `stream_ttl_days` | `7` | Retention for `hn_post` |
| `task_schedule` | `10s` | How often the ingestion task runs (e.g. `10s`, `1m`, `5m`) |
| `task_timeout` | `30s` | Max runtime per task execution |
| `lookback` | `3` | Items to look back on the very first run |
| `fetch_limit` | `20` | Max new items per task run |
| `logstore_retention_bytes` | `107374182` | Logstore size (~100 MB) |
| `logstore_retention_ms` | `300000` | Logstore retention (5 min) |

No credentials required — HN's API is public and anonymous.
