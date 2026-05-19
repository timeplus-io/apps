# Bluesky Social Analytics

Real-time analytics from Bluesky's Jetstream firehose — post volume, engagement metrics, language breakdown, top posters, and a live activity feed.

## How it works

Subscribes to the Bluesky Jetstream WebSocket (`wss://jetstream2.us-west.bsky.network/subscribe`) and ingests every commit event in the configured AT Protocol collections. Posts and activity are split into separate streams; a 1-minute mutable stream holds rolling stats for the dashboard.

## Build & install

```bash
make build                # produces bluesky.tpapp
make install              # POSTs to localhost:8000
```

Or from the repo root: `make build APP=bluesky`.

## Config

| key | type | default | notes |
|---|---|---|---|
| `jetstream_url` | string | `wss://jetstream2.us-west.bsky.network/subscribe` | Alternative endpoint if the default is unreachable |
| `wanted_collections` | list | `["app.bsky.feed.post","app.bsky.feed.like","app.bsky.graph.follow","app.bsky.feed.repost"]` | NSIDs to subscribe to |

No credentials required — Jetstream is a public, anonymous feed.

## Dashboard

`dashboards/bluesky.json` — post volume, engagement timeline, language breakdown, top posters, and a live activity table.
