# Complex Event Processing Demo

A demonstration of complex event processing in Timeplus — SQL-based fraud detection over a unified event stream plus JavaScript UDFs for pattern matching. All data is generated internally by random streams, so the app runs out of the box with no external sources.

## How it works

Two source streams (`login_events`, `purchase_events`) are unioned into a `unified_user_events` view. A materialized view applies SQL rules to flag suspicious sequences (e.g. login from a new geo followed by a high-value purchase). Two UDFs — `cep_simple_pattern` and `cep_advanced_pattern` — provide JavaScript-based pattern matching for ad-hoc queries.

## Build & install

```bash
make build
make install
```

Or from the repo root: `make build APP=cep`.

## Config

No config — everything is generated internally.

## Dashboard

`dashboards/main.json` — real-time visualization of detected events and patterns.
