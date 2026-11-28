# Dashboard JSON Specification

A dashboard is an array of panel objects. The file lives at `dashboards/main.json` (or any name declared in `manifest.yaml`) and is rendered with `[[ ]]` template delimiters before parsing.

```json
[
  { /* panel 1 */ },
  { /* panel 2 */ }
]
```

---

## Panel Object

Every panel shares the same top-level shape:

```json
{
  "id": "<unique-string>",
  "title": "Panel Title",
  "description": "",
  "position": { "h": 4, "w": 6, "x": 0, "y": 0, "nextX": 6, "nextY": 4 },
  "viz_type": "chart",
  "viz_content": "SELECT ...",
  "viz_config": { "chartType": "line", "config": { ... } }
}
```

| Field | Type | Notes |
|---|---|---|
| `id` | string | Unique within the file. Use a UUID or stable slug. |
| `title` | string | Displayed above the panel. Empty string is allowed. |
| `description` | string | Currently unused in the UI; document intent here. |
| `position` | object | Grid placement — see below. |
| `viz_type` | string | `"chart"`, `"control"`, or `"markdown"`. |
| `viz_content` | string | SQL query (chart/markdown panels). Empty for controls. |
| `viz_config` | object | Chart-type-specific config — see sections below. |

---

## Position

The dashboard uses a 12-column grid. Each row is exactly 1 unit tall. Panels can span multiple columns and rows.

```json
"position": {
  "x": 0,      // column start (0–11)
  "y": 0,      // row start (0-based)
  "w": 6,      // width in columns (1–12)
  "h": 4,      // height in rows
  "nextX": 6,  // hint: x after this panel
  "nextY": 4   // hint: y after this panel
}
```

`nextX`/`nextY` are layout hints; set them to `x+w` and `y+h` respectively for the simple non-wrapping case.

**Common widths:**
- `w: 3` — quarter width (small)
- `w: 4` — third width
- `w: 6` — half width
- `w: 12` — full width

**Common heights:**
- `h: 1` — control bar row
- `h: 3` — compact panel
- `h: 4` — standard panel
- `h: 6` — tall panel

---

## Template Variables

Dashboard JSON uses `[[ ]]` delimiters (not `{{ }}`):

| Expression | Value |
|---|---|
| `[[ .DB ]]` | Database name from `db_name` in manifest |
| `[[ .Config.key ]]` | Install-time config value |
| `[[ join "," (fromJson .Config.list_key) ]]` | Sprig function on a `list` config |
| `{{filter_product}}` | Runtime filter variable (left as-is, resolved by frontend) |

SQL in `viz_content` uses both:
- `[[ .DB ]]` for the database name (resolved at install time)
- `{{filter_*}}` for runtime values set by control panels

```json
"viz_content": "SELECT * FROM [[ .DB ]].tickers WHERE product_id = '{{filter_product}}' AND _tp_time > now() - {{filter_time_range}}"
```

---

## viz_type: `"control"`

Controls set filter variables. `viz_content` is `""`, except for a selector that takes its options from a query (see "Options from a query").

**The controls must fill row 0.** The grid compacts upward: if the controls only cover columns 0–5 of row 0, a panel placed at `x >= 6, y: 1` is lifted to `y: 0` and sits beside them. Give the controls a total width of 12 (two controls of `w: 6`, one of `w: 12`) and start every other panel at `y: 1`.

A control does not have to be in row 0. One that drives a single panel can sit right above it (a Turn list above the chart of that turn's steps), in a row of its own (`h: 1`) that controls fill in the same way.

**Every control needs a `defaultValue`.** A panel whose query uses a `{{filter_*}}` variable with no value does not run; it shows "No value assigned for variable(s)".

### Dropdown / Selector

```json
{
  "id": "ctrl-product",
  "title": "Product",
  "position": { "h": 1, "w": 3, "x": 0, "y": 0, "nextX": 3, "nextY": 1 },
  "viz_type": "control",
  "viz_content": "",
  "viz_config": {
    "chartType": "selector",
    "label": "Product",
    "labelWidth": "60",
    "target": "filter_product",
    "defaultValue": "BTC-USD",
    "inlineValues": "BTC-USD,ETH-USD,SOL-USD"
  }
}
```

| Field | Notes |
|---|---|
| `chartType` | `"selector"` |
| `label` | Text shown left of the dropdown |
| `labelWidth` | Percent of the panel width allocated to the label (string, `"0"`–`"100"`, e.g. `"50"` for 50%). Despite the name, the unit is percent, not pixels. |
| `target` | The `{{filter_*}}` variable this control writes |
| `defaultValue` | Initially selected value |
| `inlineValues` | Comma-separated list of options |
| `viz_content` (on the panel) | Optional SQL: the first column of its result is added to the options — see below |

`inlineValues` can use template functions:
```json
"inlineValues": "[[ join \",\" (fromJson .Config.product_ids) ]]"
"defaultValue": "[[ index (fromJson .Config.product_ids) 0 ]]"
```

### Options from a query

A selector lists the first column of the result of the panel's `viz_content`, in the order of the result, followed by `inlineValues` and the `defaultValue`. Use it when the options are in the data: sessions, hosts, symbols. The list has a search box, so a long list stays usable.

```json
{
  "id": "ctrl-session",
  "title": "Session",
  "position": { "h": 1, "w": 12, "x": 0, "y": 0, "nextX": 12, "nextY": 1 },
  "viz_type": "control",
  "viz_content": "SELECT replace_all(concat(format_datetime(max(event_time), '%m-%d %H:%M'), ' · ', any(agent), ' · ', session_id), char(39), '') AS session FROM table([[ .DB ]].events) GROUP BY session_id ORDER BY max(event_time) DESC LIMIT 50",
  "viz_config": {
    "chartType": "selector",
    "label": "Session",
    "labelWidth": "25",
    "target": "filter_session",
    "defaultValue": "latest",
    "inlineValues": ""
  }
}
```

- **The option is both what is shown and what is substituted.** There is no separate label and value. To show more than a bare id, build a readable text and let the queries take the id out of it: with the id as the last word, `array_element(split_by_char(' ', '{{filter_session}}'), -1)`.
- **The list is narrow** (about 35 characters before it cuts the text). Put what tells the options apart first — time, name — and a long id last.
- **The text goes into the panel queries between quotes, as it is.** Strip quote characters from the options (`replace_all(…, char(39), '')`), or one value with a `'` in it breaks every panel.
- Use a historical query (`table(...)`) with an `ORDER BY` and a `LIMIT`.
- Keep a `defaultValue`. It is added to the list when the query does not return it, which is how a word such as `latest` can stand for "the newest one".
- Prefer this to a text control whenever the user would have to copy a value from another page.
- **A selector's query can use another control's variable**, and runs again when that value changes: a Turn list `WHERE session_id = '{{filter_session}}'` follows the Session list. The dependent control keeps its chosen value when the first one changes, so make the panel queries fall back when that value no longer belongs (`if(count_if(turn = picked) > 0, picked, <latest turn>)`).

### Text Input

```json
{
  "viz_config": {
    "chartType": "text",
    "label": "Source IP",
    "labelWidth": "50",
    "target": "filter_src_ip",
    "defaultValue": "203.0.113.67",
    "inlineValues": ""
  }
}
```

Use `"chartType": "text"` for a free-form text field. Do NOT use `"text_input"` — that value silently falls through to the selector renderer and shows a dropdown. The empty `"inlineValues": ""` is required (match the UI builder's emitted shape exactly).

A text control with an empty `defaultValue` stops every panel that uses it. When "nothing typed" should mean something (the latest session, all hosts), give the control a word for it and handle that word in SQL:

```json
"defaultValue": "latest"
```
```sql
WHERE session_id = (SELECT if('{{filter_session}}' IN ('', 'latest'), arg_max(session_id, event_time), '{{filter_session}}') FROM table([[ .DB ]].events))
```

---

## viz_type: `"markdown"`

Simple Markdown panel. Markdown source lives in `viz_config.mdString`. Can optionally run a SQL query (`viz_content`) and interpolate the **latest row's** column values using `{{column_name}}` in the template.

```json
{
  "id": "md-intro",
  "title": "",
  "position": { "h": 2, "w": 12, "x": 0, "y": 0, "nextX": 12, "nextY": 2 },
  "viz_type": "markdown",
  "viz_content": "SELECT price FROM tickers LIMIT 1",
  "viz_config": {
    "mdString": "## Live Price\n\nCurrent BTC price: **${{price}}**"
  }
}
```

- `viz_config.mdString` — Markdown source with optional `{{column_name}}` placeholders
- `viz_content` — SQL query. **Must not be empty even for static text** — set it to `"SELECT 1"` if the markdown has no interpolation. An empty string leaves the panel stuck loading.
- Interpolation uses only the **last row** of the query result

---

## viz_type: `"chart"` — `chartType: "md"` (Markdown viz)

A more powerful Markdown panel that runs a SQL query and interpolates column values into the template. Use this instead of `viz_type: "markdown"` when you need key-based lookups or streaming update modes.

**Static markdown still needs a query.** Both `viz_type: "markdown"` and `chartType: "md"` panels treat `viz_content` as required — an empty string leaves the panel stuck on a loading state. For pure-text headers/instructions with no interpolation, set `"viz_content": "SELECT 1"` as a no-op stub.

```json
{
  "id": "md-status",
  "title": "Current Status",
  "position": { "h": 3, "w": 6, "x": 0, "y": 0, "nextX": 6, "nextY": 3 },
  "viz_type": "chart",
  "viz_content": "SELECT product_id, price, volume FROM [[ .DB ]].tickers WHERE _tp_time > now() - 1m",
  "viz_config": {
    "chartType": "md",
    "config": {
      "content": "## {{product_id}}\n\nPrice: **${{price}}**\nVolume: {{volume}}",
      "updateMode": "all",
      "updateKey": ""
    }
  }
}
```

### Interpolation modes

**Default (`updateMode: "all"` or `"time"`)** — inserts values from the **last row** of the query result:
```
Price: **${{price}}**
```

**Key mode (`updateMode: "key"`)** — look up a specific row by key and field using `{{@keyValue::fieldName}}`:
```
BTC Price: **${{@BTC-USD::price}}**
ETH Price: **${{@ETH-USD::price}}**
```
This pulls the `price` value from the row where `updateKey` column equals `BTC-USD` (or `ETH-USD`). Useful for showing multiple values from a mutable stream side by side.

```json
"viz_content": "SELECT product_id, price FROM table([[ .DB ]].latest_prices)",
"viz_config": {
  "chartType": "md",
  "config": {
    "content": "| Symbol | Price |\n|---|---|\n| BTC | ${{@BTC-USD::price}} |\n| ETH | ${{@ETH-USD::price}} |",
    "updateMode": "key",
    "updateKey": "product_id"
  }
}
```

| Key | Type | Notes |
|---|---|---|
| `content` | string | Markdown template with `{{col}}` or `{{@key::col}}` placeholders |
| `updateMode` | string | `"all"` replace all, `"key"` look up by key, `"time"` append |
| `updateKey` | string | Column name for key-mode lookups |

A `md` panel is the right panel for **one record**: a summary of the session, host or order a control picked. A one-row table wastes its width on headers and hides half its columns behind a scrollbar. Sizing: the text scrolls inside the panel when it is taller than it; a panel of `h: 2` with a title holds two lines of text, so put several facts on a line, separated by ` · `, and check the render.

---

## viz_type: `"chart"`

All chart panels share:
```json
"viz_type": "chart",
"viz_content": "<Timeplus streaming SQL>",
"viz_config": {
  "chartType": "<type>",
  "config": { ... }
}
```

Chart types: `line`, `area`, `bar`, `column`, `singleValue`, `table`, `ohlc`, `geo`, `md` (Markdown viz — see dedicated section above), `grammar` (3.2+ — generic Vistral grammar; use when no fixed type fits).

---

### `line` and `area`

Time-series charts. Requires a datetime column for X, numeric column for Y.

> **Multi-series queries must set `color`.** If your SELECT returns multiple series (e.g. `SELECT time, stock_id, close FROM ...` — one line per `stock_id`), set `"color": "stock_id"` (the series/category column). Leaving it as `""` silently collapses all series into a single overlapping line — the chart renders but is unreadable.

```json
"viz_config": {
  "chartType": "line",
  "config": {
    "xAxis": "time",
    "yAxis": "price",
    "color": "stock_id",  // ← series column; required when the query returns >1 series
    "xRange": "Infinity",
    "xFormat": "",
    "xTitle": "",
    "yTitle": "",
    "yRange": { "min": null, "max": null },
    "lineStyle": "curve",
    "dataLabel": false,
    "showAll": false,
    "legend": false,
    "points": false,
    "gridlines": true,
    "unit": { "position": "left", "value": "" },
    "fractionDigits": 2,
    "colors": ["#ED64A6", "#F0BE3E", "#DA4B36", "#9A1563", "#FF4A71",
                "#D12D50", "#8934D9", "#D53F8C", "#F7775A", "#8934D9"],
    "yTickLabel": { "maxChar": 25 }
  }
}
```

| Key | Type | Notes |
|---|---|---|
| `xAxis` | string | Column name — must be datetime type |
| `yAxis` | string | Column name — must be numeric type |
| `color` | string | **Required for multi-series.** Column name that distinguishes series (e.g. `"stock_id"`, `"region"`). Empty = single-series only. |
| `xRange` | string | Minutes to show: `"1"`, `"5"`, `"60"`, `"Infinity"` (all) |
| `xFormat` | string | Moment.js format. Use `""` (auto) for any panel whose query can span more than one day — including all `seek_to='earliest'` panels. Reserve `"LT"` (time-of-day only) for short-window panels filtered with `WHERE time > now() - Xm`. |
| `lineStyle` | string | `"curve"` or `"straight"` |
| `dataLabel` | bool | Show data point labels |
| `points` | bool | Show dots at each data point |
| `legend` | bool | Show legend (only when `color` is set) |
| `gridlines` | bool | Show horizontal gridlines |
| `yRange` | object | `{ "min": null, "max": null }` — null = auto |

Use `area` for the same config to get a filled area chart.

A line joins its points across periods with no row, so sparse data (a few buckets with events, hours apart) draws long diagonals that look like a trend. For counts over time on sparse data use a `column` chart; keep lines for values that exist in most buckets (ratios, latency, sizes).

---

### `bar` and `column`

Categorical charts. `bar` = horizontal bars, `column` = vertical bars.

```json
"viz_config": {
  "chartType": "bar",
  "config": {
    "xAxis": "repo",
    "yAxis": "count",
    "color": "",
    "groupType": "stack",
    "updateMode": "all",
    "updateKey": "",
    "xFormat": "",
    "xTitle": "",
    "yTitle": "",
    "dataLabel": true,
    "legend": false,
    "gridlines": true,
    "unit": { "position": "left", "value": "" },
    "fractionDigits": 0,
    "colors": ["#ED64A6", "#F0BE3E", "#DA4B36", "#9A1563", "#FF4A71",
                "#D12D50", "#8934D9", "#D53F8C", "#F7775A", "#8934D9"],
    "yTickLabel": { "maxChar": 25 },
    "xTickLabel": { "maxChar": 20 }
  }
}
```

| Key | Type | Notes |
|---|---|---|
| `xAxis` | string | Category column (string or datetime) |
| `yAxis` | string | Value column (numeric) |
| `color` | string | Column that splits each bar into series. **Needs `updateMode: "key"` with a key that is unique per row — see below.** |
| `groupType` | string | `"stack"` or `"dodge"` (side by side) |
| `updateMode` | string | `"all"` replace all, `"key"` upsert by key, `"time"` append by time |
| `updateKey` | string | Column for key-based updates (e.g. `"emit_version()"`) |
| `xFormat` | string | Format string for datetime x-axis labels. It did not take effect on a `column` chart in the console (Timeplus 3.5): the labels stayed full ISO timestamps. Select the x value as text instead — see below. |
| `xTickLabel.maxChar` | number | Max characters on x-axis labels |

**Update modes:**
- `"all"` — replace the entire dataset on each query result (historical queries)
- `"time"` — append data; use with a time column as `updateKey` for streaming leaderboards
- `"key"` — upsert rows by `updateKey` value (for mutable streams, and for **any chart with more than one row per x value**)

> **A bar or column chart with a series must update by a key that is unique per row.** In `updateMode: "all"` the chart keeps ONE row per x value. A query that returns one row per series for each x (`time, activity, events`) then draws a single series in every bar and silently drops the rest: the chart renders, the legend lists every series, and the bars are simply not stacked. `groupType: "dodge"` loses the rows the same way. Nothing fails at install.
>
> Return a column made of the x value and the series together, and update by it:
>
> ```sql
> SELECT *, concat(to_string(time), ' ', to_string(activity)) AS k
> FROM (SELECT ... AS time, ... AS activity, count() AS events FROM ... GROUP BY time, activity)
> ORDER BY time
> ```
> ```json
> "xAxis": "time", "yAxis": "events", "color": "activity", "groupType": "stack",
> "updateMode": "key", "updateKey": "k"
> ```
>
> A single-series chart (one row per x) is fine with `updateMode: "all"`. To check a multi-series chart, compare one bar with the query result: the bar's height must be the sum of that x value's rows.

**Time on the x axis of a column chart.** Select the bucket as text, so the label is what you want and the order is the query's:

```sql
SELECT format_datetime(window_start, '%m-%d %H:%M') AS time, count() AS events
FROM tumble(table([[ .DB ]].events), event_time, 5m)
WHERE event_time > now() - {{filter_time_range}}
GROUP BY window_start ORDER BY window_start
```

A fixed bucket gives too many bars on a long range (5 minutes over 7 days is 2,016). To keep at most 60 bars whatever the range, derive the bucket from the range, with a floor of one minute:

```sql
-- step in seconds: the selected range divided by 60, at least 60
format_datetime(to_datetime(int_div(to_unix_timestamp(event_time),
    greatest(60, int_div(date_diff('second', now() - {{filter_time_range}}, now()), 60)))
  * greatest(60, int_div(date_diff('second', now() - {{filter_time_range}}, now()), 60))), '%m-%d %H:%M') AS time
```

Only buckets with at least one row are drawn; an empty period shows as missing bars, not as a gap.

---

### `singleValue`

Displays a single large number with optional sparkline and delta indicator.

```json
"viz_config": {
  "chartType": "singleValue",
  "config": {
    "value": "count()",
    "color": "blue",
    "sparkline": true,
    "sparklineColor": "blue",
    "delta": true,
    "increaseColor": "green",
    "decreaseColor": "red",
    "fontSize": 64,
    "fractionDigits": 0,
    "unit": { "position": "right", "value": "" }
  }
}
```

| Key | Type | Notes |
|---|---|---|
| `value` | string | Column name (must be numeric) — often matches the SELECT alias |
| `color` | string | Color of the main value (CSS color name or hex) |
| `sparkline` | bool | Show a mini trend chart |
| `sparklineColor` | string | Sparkline color |
| `delta` | bool | Show change indicator vs previous value |
| `increaseColor` | string | Color when delta is positive |
| `decreaseColor` | string | Color when delta is negative |
| `fontSize` | number | Font size in px |
| `fractionDigits` | number | Decimal places |
| `unit.value` | string | Unit label (e.g. `"ms"`, `"%"`) |
| `unit.position` | string | `"left"` or `"right"` |

---

### `table`

Tabular view with per-column styling, trend indicators, and conditional formatting.

```json
"viz_config": {
  "chartType": "table",
  "config": {
    "rowCount": 5,
    "updateMode": "all",
    "updateKey": "",
    "tableWrap": false,
    "tableStyles": {
      "product_id": {
        "name": "",
        "show": true,
        "width": 139,
        "trend": false,
        "miniChartType": "",
        "conditions": [],
        "highlightRow": false,
        "increaseColor": "green",
        "decreaseColor": "red"
      },
      "price": {
        "name": "",
        "show": true,
        "width": 100,
        "trend": true,
        "miniChartType": "",
        "conditions": [],
        "highlightRow": false,
        "increaseColor": "green",
        "decreaseColor": "red"
      }
    }
  }
}
```

`tableStyles` keys are column names from the query result.

| Key | Type | Notes |
|---|---|---|
| `rowCount` | number | Rows to display: 5, 10, 20, 30, 50, 100. **Default 5, and the table shows the LAST `rowCount` rows of the result** — see below. |
| `updateMode` | string | Same as bar/column: `"all"`, `"key"`, `"time"` |
| `updateKey` | string | Key column for `"key"` update mode |
| `tableWrap` | bool | Wrap long cell text |
| `tableStyles.<col>.show` | bool | Show/hide column |
| `tableStyles.<col>.width` | number | Column width in px |
| `tableStyles.<col>.trend` | bool | Color cell green/red based on value change |
| `tableStyles.<col>.name` | string | Override display name (empty = use column name) |

**Minimal table config** (omit `tableStyles` entirely and it auto-generates from query headers):
```json
"viz_config": { "chartType": "table", "config": { "rowCount": 100, "updateMode": "all", "updateKey": "", "tableWrap": false } }
```

**A table shows the last `rowCount` rows of its result, and opens scrolled to its last row.** With `{ "chartType": "table" }` alone, `rowCount` is 5: a query with `ORDER BY score DESC LIMIT 50` shows the five *lowest* scores. So:

- Set `rowCount` at or above the query's `LIMIT` (the maximum is 100), and keep `LIMIT` at 100 or less.
- **A ranking** ("top sessions"): return few enough rows to fit the panel without scrolling, best first. About 8 rows fit a panel of `h: 5`, 6 fit `h: 4`.
- **A list** (events, sessions, a log): order oldest first, so the newest rows are the ones in view. To list the newest 100, take them newest first in a subquery and re-order outside: `SELECT * FROM (SELECT ... ORDER BY time DESC LIMIT 100) ORDER BY time`.
- `updateMode: "key"` does not change the scrolling. `updateMode: "time"` on a historical query showed one row.

---

### `ohlc`

Candlestick chart for financial data. Query **must** return columns named exactly: `time`, `open`, `high`, `low`, `close`.

```json
"viz_config": {
  "chartType": "ohlc",
  "config": {
    "xRange": "Infinity",
    "yRange": { "min": null, "max": null }
  }
}
```

| Key | Type | Notes |
|---|---|---|
| `xRange` | string | Minutes to display: `"1"`, `"60"`, `"Infinity"` |
| `yRange.min` | number\|null | Y-axis minimum (null = auto) |
| `yRange.max` | number\|null | Y-axis maximum (null = auto) |

**Required SQL shape:**
```sql
SELECT
  window_start AS time,
  earliest(price) AS open,
  latest(price)   AS close,
  max(price)      AS high,
  min(price)      AS low
FROM tumble(stream, interval)
GROUP BY window_start
```

---

### `geo`

Map scatter chart. Requires two numeric columns for longitude and latitude.

```json
"viz_config": {
  "chartType": "geo",
  "config": {
    "longitude": "lon",
    "latitude": "lat",
    "color": "category",
    "updateMode": "all",
    "updateKey": "",
    "visibleColumns": ["city", "category"],
    "colors": ["#ED64A6", "#F0BE3E", "#DA4B36"],
    "opacity": 0.8,
    "zoom": 4,
    "center": [20, 0],
    "size": {
      "key": "",
      "value": 4,
      "range": [2, 20]
    }
  }
}
```

| Key | Type | Notes |
|---|---|---|
| `longitude` | string | Column name for longitude (numeric) |
| `latitude` | string | Column name for latitude (numeric) |
| `color` | string | Column for dot coloring |
| `visibleColumns` | string[] | Columns shown in the tooltip popup |
| `zoom` | number | Initial map zoom level (typical range 1–18) |
| `center` | [lat, lon] | Initial map center — **latitude first, then longitude** (Vistral convention; do NOT swap). The map opens here on first load and stays put — there's no auto-fit-to-data option exposed. Pick values inside your data's bounding box. |
| `opacity` | number | Dot opacity 0–1 |
| `size.key` | string | Column to scale dot size by (empty = fixed size) |
| `size.value` | number | Fixed dot size (when `size.key` is empty) |
| `size.range` | [min, max] | Min/max dot size when `size.key` is set |

**Picking `center` and `zoom`.** The geo panel has no `autoFit` option in the dashboard JSON — the initial view is fixed. Compute it from your data:

```sql
-- Find the midpoint of your data's bounding box
SELECT
  round((min(latitude)  + max(latitude))  / 2, 4) AS center_lat,
  round((min(longitude) + max(longitude)) / 2, 4) AS center_lon
FROM table(<your_mutable_stream>);
```

Then set `"center": [<center_lat>, <center_lon>]` (lat first!) and pick `zoom` so the bounding box fits comfortably. Rough rule: each step of zoom halves the visible extent. Zoom 11 ≈ 50 km wide, 12 ≈ 25 km, 13 ≈ 12 km, 14 ≈ 6 km.

**Common bug:** swapping `[lat, lon]` ↔ `[lon, lat]` lands you on the opposite side of the world. If your map opens far from your data, that's the cause.

---

### `grammar` (Timeplus 3.2+)

A generic, spec-driven chart type backed by the [Vistral](https://github.com/timeplus-io/vistral) grammar engine. Use when no fixed `chartType` covers what you need — scatter (point mark with numeric x), layered marks, categorical band-axis bars with band scale + key-based update, stacked area via the `stackY` transform, log-scale lines, etc.

**For the underlying grammar — full `VistralSpec` shape, every mark type, transform, scale, encode channel, and streaming option — see the Vistral skill:**
[`vistral/agentskill/SKILL.md`](https://github.com/timeplus-io/vistral/blob/main/agentskill/SKILL.md)

Everything you write in `advancedSpec` (and what the form-builder fields map to) is documented there. This section below covers only the dashboard-side `viz_config.config` wrapper that exposes the grammar through a form.

```json
"viz_config": {
  "chartType": "grammar",
  "config": {
    "renderInterval": 500,
    "updateMode": "all",
    "updateKey": "",

    "markType": "line",
    "xField": "_tp_time",
    "yField": ["value"],
    "colorField": "",
    "sizeField": "",

    "xScaleType": "time",
    "yScaleType": "linear",

    "temporalMode": "axis",
    "temporalRange": 1,

    "streamMaxItems": 600,
    "streamMode": "append",
    "throttleMs": 100,

    "xAxisTitle": "",
    "yAxisTitle": "Value",
    "legendPosition": "top",

    "advancedSpec": ""
  }
}
```

| Key | Type | Notes |
|---|---|---|
| `markType` | `'line' \| 'area' \| 'interval' \| 'point' \| 'rect'` | Mark to draw. `interval` is a bar; `point` is a scatter mark. |
| `xField` | string | Column for x encoding. |
| `yField` | string \| string[] | Column(s) for y. Single-element arrays are unwrapped to a scalar; arrays with >1 entry are passed through for multi-series marks. |
| `colorField` | string | Optional column for color encoding (groups marks by category). |
| `sizeField` | string | Optional column for size encoding (point/interval). |
| `xScaleType` | `'time' \| 'linear' \| 'band' \| 'ordinal' \| 'log'` \| `''` | x-axis scale. Use `band` for categorical x on `interval` marks. Empty = auto. |
| `yScaleType` | `'linear' \| 'log'` \| `''` | y-axis scale. Empty = auto. |
| `temporalMode` | `'' \| 'axis' \| 'frame' \| 'key'` | Streaming behavior. `axis` = sliding window on x-axis; `frame` = replace on each tick; `key` = update by key column. Empty = none. |
| `temporalRange` | number\|null | **Minutes** (not ms) for the sliding window when `temporalMode === 'axis'`. |
| `streamMaxItems` | number\|null | Cap on rows kept in the chart buffer. |
| `streamMode` | `'append' \| 'replace'` \| `''` | Append new rows or replace the buffer on each tick. |
| `throttleMs` | number\|null | Throttle window for rerenders, in milliseconds. |
| `xAxisTitle` / `yAxisTitle` | string | Axis titles (empty = no title). |
| `legendPosition` | `'top' \| 'bottom' \| 'left' \| 'right' \| 'hidden'` | Legend placement. Use `'hidden'` (not `'none'`) to suppress. |
| `advancedSpec` | string (JSON) | Optional raw `VistralSpec` deep-merged on top of the form-derived spec. **Arrays are replaced atomically** by `mergeDeepRight`, so providing `marks` here overrides the entire mark array including the form-built encode — declare every mark you want explicitly when you use it. |

**Common patterns**

Scatter with color + size encoding:
```json
{
  "markType": "point",
  "xField": "sepal_length",
  "yField": ["sepal_width"],
  "colorField": "species",
  "sizeField": "petal_length",
  "xScaleType": "linear",
  "yScaleType": "linear",
  "temporalMode": ""
}
```

Streaming line with a 1-minute sliding window:
```json
{
  "markType": "line",
  "xField": "_tp_time",
  "yField": ["value"],
  "xScaleType": "time",
  "temporalMode": "axis",
  "temporalRange": 1,
  "streamMaxItems": 600,
  "streamMode": "append",
  "throttleMs": 100
}
```

Categorical bar by group, key-based update (one row per category):
```json
{
  "markType": "interval",
  "xField": "category",
  "yField": ["value"],
  "colorField": "category",
  "xScaleType": "band",
  "updateMode": "key",
  "updateKey": "category",
  "streamMode": "replace"
}
```

Layered line + points (advancedSpec, atomic mark replacement):
```json
{
  "markType": "line",
  "xField": "_tp_time",
  "yField": ["value"],
  "advancedSpec": "{\"marks\":[{\"type\":\"line\",\"encode\":{\"x\":\"_tp_time\",\"y\":\"value\"},\"style\":{\"strokeWidth\":2}},{\"type\":\"point\",\"encode\":{\"x\":\"_tp_time\",\"y\":\"value\"},\"style\":{\"fillOpacity\":0.6}}]}"
}
```

Stacked area (transform via advancedSpec):
```json
{
  "markType": "area",
  "xField": "_tp_time",
  "yField": ["value"],
  "colorField": "series",
  "advancedSpec": "{\"transforms\":[{\"type\":\"stackY\"}]}"
}
```

Trace waterfall (Gantt): one horizontal bar per row, from a start to an end. An interval mark takes the start as `y` and the end as `y1`; a transposed coordinate lays the bars sideways. Used for the turns and steps of a session in `apps/agentguard/dashboards/session_trace.json`.

```json
{
  "markType": "interval",
  "xField": "step",
  "yField": ["start_s"],
  "colorField": "kind",
  "xScaleType": "band",
  "yScaleType": "linear",
  "temporalMode": "",
  "streamMode": "replace",
  "legendPosition": "top",
  "advancedSpec": "{\"marks\":[{\"type\":\"interval\",\"encode\":{\"x\":\"step\",\"y\":\"start_s\",\"y1\":\"end_s\",\"color\":\"kind\"},\"style\":{\"maxWidth\":18},\"tooltip\":{\"items\":[{\"field\":\"seconds\",\"name\":\"seconds\"},{\"field\":\"input\",\"name\":\"input\"}]}}],\"coordinate\":{\"transforms\":[{\"type\":\"transpose\"}]},\"scales\":{\"x\":{\"type\":\"band\"},\"y\":{\"type\":\"linear\",\"nice\":true}},\"axes\":{\"x\":{\"title\":false},\"y\":{\"title\":\"seconds from the start\"}}}"
}
```

- **The query returns one row per bar**: a label unique per row and in display order (`concat(lpad(to_string(n), 3, '0'), ' ', name)`), the start and the end as numbers on one scale (seconds from the first row), and any column the tooltip shows. Rows are drawn top to bottom in the order of the result.
- **Start and end as offsets, not timestamps.** `round((start_ms - first_ms) / 1000, 2)`. Give a moment (an event without a duration) a small width (`greatest(end_ms, start_ms + 200)`), or it is not drawn.
- **`tooltip.items`** names the columns to show when a bar is pointed at, so the text a table would hold (input, result, error) can live in the tooltip. Keep each to a few hundred characters and on one line (`replace_regex(col, '\\s+', ' ')`).
- **`style.maxWidth`** keeps bars thin when there are few rows in a tall panel.
- **Scope the time axis.** One axis over a whole session leaves idle time between turns and shrinks every bar to a sliver; draw one turn (one trace) at a time and let a control pick it.
- **A chart does not scroll inside its panel.** G2's `scrollbar` and `slider` options in `g2Overrides` have no effect, and a `g2Overrides.height` larger than the panel is clipped. A panel's height is also fixed by its `position.h`: it does not grow or shrink with the number of rows. Pick a height for the usual case (`h: 5` suits up to about 25 rows; more rows are drawn denser, with fewer labels), cap the rows, and put the detail in the tooltip.
- A window function next to scalar subqueries in one `SELECT`, or used inside another expression (`if(x != '', min(t) OVER (PARTITION BY x), t)`), failed with `Not found column`. Select the window function as a column of its own in an inner query (`min(t) OVER (PARTITION BY x) AS first_t`, `row_number() OVER (ORDER BY start_ms) AS n`) and compute the rest outside.
- **Grouping rows under a parent** (the steps of a sub-agent under the sub-agent): give every row a sort key that is the parent's start for a child and its own start otherwise, add a row for the parent with a lower rank, number the rows by `(group key, rank, start)`, and mark a child in its label (`concat('└ ', name)`). The chart has flat rows: it shows order and marks, not indentation.

**Gotchas**
- `temporalRange` is **minutes**, not milliseconds. Setting it to `60000` gives you a 60000-minute (~41-day) window and your sliding chart will appear empty until ~41 days pass.
- `legendPosition: 'hidden'` not `'none'`. The Selector engine reserves `'none'` for its placeholder item and silently coerces it to `''`.
- The form's y-field picker is multi-select, but Vistral's grammar wants a scalar `y` for single-series marks. The translator handles this by unwrapping length-1 arrays — so `yField: ["value"]` and `yField: "value"` both render correctly.
- `xField` and `colorField` UI pickers filter to non-numeric columns by default. To use a numeric column for x (scatter) or color (sequential), you have to author the JSON directly or set the value via `advancedSpec` — the form won't offer numeric columns there.
- When `advancedSpec` supplies `marks`, the array fully replaces the form-built marks. Declare every layer you want; don't expect the form's mark to be preserved underneath.
- For a known-bad config (missing mark type or x/y encode), the panel renders an inline error banner instead of throwing — useful while authoring, but check the panel for that banner if your chart appears blank.

---

## Default Color Palette

Use this standard 10-color palette for consistency:

```json
"colors": [
  "#ED64A6", "#F0BE3E", "#DA4B36", "#9A1563", "#FF4A71",
  "#D12D50", "#8934D9", "#D53F8C", "#F7775A", "#8934D9"
]
```

---

## updateMode Reference

| Mode | When to use | updateKey value |
|---|---|---|
| `"all"` | Historical (batch) queries; the full result replaces the chart | `""` |
| `"time"` | Streaming aggregations with `emit_version()` — append new result sets | `"emit_version()"` or a timestamp column |
| `"key"` | Mutable streams — upsert rows by primary key column | primary key column name |
| `"key"` | A bar or column chart with a series (`color`), on any query: more than one row per x value | a column unique per row, e.g. `concat(to_string(x), ' ', to_string(series)) AS k` |

**Streaming leaderboard pattern** (append mode):
```sql
SELECT repo, count(*) AS cnt, emit_version()
FROM stream WHERE _tp_time > now() - 10m
GROUP BY repo ORDER BY cnt DESC LIMIT 5 BY emit_version()
```
```json
"updateMode": "time", "updateKey": "emit_version()"
```

---

## Full Example: Market Data Dashboard Panel

```json
[
  {
    "id": "ctrl-product",
    "title": "",
    "position": { "h": 1, "w": 3, "x": 0, "y": 0, "nextX": 3, "nextY": 1 },
    "viz_type": "control",
    "viz_content": "",
    "viz_config": {
      "chartType": "selector",
      "label": "Product",
      "labelWidth": "60",
      "target": "filter_product",
      "defaultValue": "[[ index (fromJson .Config.product_ids) 0 ]]",
      "inlineValues": "[[ join \",\" (fromJson .Config.product_ids) ]]"
    }
  },
  {
    "id": "chart-price",
    "title": "Live Price",
    "position": { "h": 4, "w": 12, "x": 0, "y": 1, "nextX": 12, "nextY": 5 },
    "viz_type": "chart",
    "viz_content": "SELECT _tp_time AS time, price FROM [[ .DB ]].tickers WHERE product_id = '{{filter_product}}' AND _tp_time > now() - 5m",
    "viz_config": {
      "chartType": "line",
      "config": {
        "xAxis": "time",
        "yAxis": "price",
        "color": "",
        "xRange": "5",
        "xFormat": "HH:mm:ss",
        "lineStyle": "curve",
        "dataLabel": false,
        "points": false,
        "legend": false,
        "gridlines": true,
        "unit": { "position": "left", "value": "$" },
        "fractionDigits": 2,
        "yRange": { "min": null, "max": null },
        "yTickLabel": { "maxChar": 25 },
        "xTitle": "",
        "yTitle": "",
        "colors": ["#ED64A6","#F0BE3E","#DA4B36","#9A1563","#FF4A71",
                   "#D12D50","#8934D9","#D53F8C","#F7775A","#8934D9"]
      }
    }
  }
]
```

---

## Common Mistakes

| Mistake | Fix |
|---|---|
| Using `{{ .DB }}` in dashboard JSON | Use `[[ .DB ]]` — dashboard uses `[[ ]]` delimiters |
| Flat chart config like `{ "chartType": "line", "x": "...", "y": [...] }` | Wrap fields under `config` and use `xAxis` / `yAxis` (not `x` / `y`). The renderer throws `VizConfigError: Missing or invalid config field: xAxis` for flat shapes. |
| OHLC query doesn't have column named `time` | Alias: `window_start AS time` |
| Selector control writes wrong filter name | `target` must match `{{filter_*}}` in SQL exactly |
| Table shows no data | Check `updateMode` — use `"key"` for mutable streams |
| Streaming leaderboard doesn't update | Set `updateMode: "time"`, `updateKey: "emit_version()"` |
| `inlineValues` not reflecting config | Use `[[ join "," (fromJson .Config.list_key) ]]` |
| Stacked (or dodged) bar/column chart shows one colour per bar | The chart keeps one row per x value in `updateMode: "all"`. Add a key unique per row and set `updateMode: "key"` — see "bar and column" |
| Table shows 5 rows, and the wrong ones (the bottom of a ranking) | A table shows the last `rowCount` rows (default 5). Set `rowCount`, and size or order the result — see "table" |
| A panel sits beside the controls instead of below them | The controls must fill the 12 columns of row 0 |
| Every panel says "No value assigned for variable(s)" | A control has an empty `defaultValue` (typically a text control) |
| The user has to paste an id into a text control | Make it a selector with its options from a query — see "Options from a query" |
| A table that always has one row (a summary of the selected item) | Use a `md` panel: the query returns the row, the `content` lays its columns out as text with `{{column}}`. Format dates and numbers in SQL |
| Column chart x axis shows `2026-11-27T16:35:00Z` | Select the time bucket as text with `format_datetime` |
| Line chart draws long diagonals between far-apart points | A line joins points across empty periods; use a column chart for counts on sparse data |
| `Aggregate function any(col) is found in WHERE` | `any(col) AS col` plus a filter on `col`: the alias replaces the column in `WHERE`. Alias it under another name |
| `Aggregate function min(x) is found inside another aggregate function` | `min(x) AS x` next to another aggregate of `x` in the same `SELECT`: the alias replaces the column there too. Aggregate under other names in an inner query and rename outside |
| Histogram bars are in the wrong order | A bar or column chart draws rows in the order of the result. Bucket in SQL (`multi_if(v < 1000, 0, v < 2000, 1, …) AS i` with a label column), and order by `i`, not by the label or the count |

---

## Checking a dashboard

A wrong dashboard installs cleanly and renders: the panel is just wrong. Two checks catch what the JSON cannot show.

1. **Run every query.** Replace `[[ .DB ]]` and each `{{filter_*}}` with real values and run each `viz_content` against an instance with data, for every value of each selector. This finds SQL errors and missing chart columns.
2. **Look at every panel, and compare with the data.** Install the app, open each dashboard, and for each chart compare one bar, one line or the first rows of one table with the result of its query. This finds dropped series, tables showing the wrong rows, panels in the wrong place and unreadable axes — none of which fail a query.
