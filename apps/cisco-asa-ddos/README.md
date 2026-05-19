# Cisco ASA DDoS Detection Demo

Real-time DDoS detection from simulated Cisco ASA firewall logs. Generates background traffic and a controllable attack stream, parses raw syslog into structured fields, then applies dynamic per-IP baselines (overall and hourly) to flag spike ratios in real time.

## How it works

Random streams produce background syslog traffic and attacker traffic at configurable rates. A parser MV extracts structured fields from raw ASA logs. Two mutable streams hold per-source-IP baselines — one overall, one hourly — that the spike-detection logic compares incoming rates against. Alerts fire when a source IP's current rate exceeds its baseline by more than `spike_threshold`×.

## Build & install

```bash
make build
make install
```

Or from the repo root: `make build APP=cisco-asa-ddos`.

## Config

| key | default | notes |
|---|---|---|
| `alert_webhook_url` | `http://localhost/alert` | Webhook called on alert |
| `spike_threshold` | `10` | Spike multiple over baseline that triggers an alert |
| `attacker_src_ip` | `203.0.113.67` | Source IP for the simulated attacker |
| `background_eps` | `100` | Background traffic rate (events/sec, many random IPs) |
| `sim_normal_eps` | `5` | Attacker IP baseline rate (events/sec) |
| `sim_attack_eps` | `500` | Attack burst rate (events/sec) when attack MV is resumed |
| `retention_hours` | `4` | TTL on traffic streams |
| `logstore_retention_bytes` | `107374182` | Logstore size per stream (~100 MB) |
| `logstore_retention_ms` | `300000` | Logstore retention (5 min) |

## Dashboard

`dashboards/main.json` — spike-ratio monitoring, baseline tables, and a live traffic feed.
