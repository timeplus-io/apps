# GitHub Activity Monitor

Real-time pipeline that streams public GitHub events into Timeplus for live analytics — pushes, pull requests, issues, stars, forks, and other activity across the public timeline.

## How it works

A Python external stream uses `PyGithub` to poll the public events API, normalizes each event, and writes it into the `github_events` stream (7-day TTL) via a materialized view.

## Build & install

```bash
make build
make install
```

Or from the repo root: `make build APP=github`.

## Config

| key | type | notes |
|---|---|---|
| `github_token` | string (secret) | Required. GitHub personal access token with `public_repo` scope. Unauthenticated requests are heavily rate-limited. |

## Dashboard

`dashboards/main.json` — real-time view of GitHub public events.
