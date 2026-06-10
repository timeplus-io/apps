# Hacker News RAG Q&A Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add RAG-based question answering to the `hacker-news` app: an embedding UDF, a vector-store stream populated by an MV, an LLM answer UDF, a one-statement RAG query, and a Q&A dashboard.

**Architecture:** New posts flow `hn_post → mv_hn_story_embedding (calls embed_text UDF) → hn_story (embedding array(float32))`. Questions are answered ad-hoc: embed the question, brute-force `cosine_distance` top-k over `table(hn_story)`, assemble context in SQL, call `rag_answer` UDF. Spec: `docs/superpowers/specs/2026-06-10-hacker-news-rag-design.md`.

**Tech Stack:** Timeplus DDL (Go-templated SQL), Python UDFs using `requests` against an OpenAI-compatible API, `.tpapp` packaging, dashboard JSON.

**Prerequisites (ask the user if missing — do not fake these):**
- A running Timeplus instance. Verify: `curl -s -m 3 "http://localhost:8123/"` returns `Ok.` and `curl -s -m 3 -o /dev/null -w '%{http_code}' http://localhost:8000/default/api/v1beta2/apps` returns a 2xx/4xx (not connection refused). If either is connection-refused, STOP and ask the user to start Timeplus.
- `TIMEPLUS_USER`/`TIMEPLUS_PASSWORD` env vars (default `default` / empty if unset).
- `LLM_API_KEY` env var holding a real OpenAI-compatible API key for install-time config. If unset, STOP and ask the user.

All SQL verification uses:

```bash
run_sql() { curl -s "http://localhost:8123/?default_format=JSONEachRow" -u "${TIMEPLUS_USER:-default}:${TIMEPLUS_PASSWORD:-}" --data-binary @-; }
```

---

### Task 1: Verify vector-search function names on the live instance

The whole design assumes `cosine_distance(array, array)` and `array_string_concat(array, sep)` exist. Verify before writing any DDL.

**Files:** none (verification only)

- [ ] **Step 1: Probe the distance function**

```bash
echo "SELECT cosine_distance([1.0,0.0],[0.0,1.0]) AS d" | run_sql
```

Expected: `{"d":1}` (orthogonal vectors → cosine distance 1).
If it errors with unknown function, try `cosineDistance`, then `1 - dot_product(a,b)/(l2_norm(a)*l2_norm(b))`. Record the working spelling and use it in ALL later tasks (006 is unaffected; the RAG query and dashboard panels are affected).

- [ ] **Step 2: Probe the string-join function**

```bash
echo "SELECT array_string_concat(['a','b'], '---') AS s" | run_sql
```

Expected: `{"s":"a---b"}`. If unknown, try `arrayStringConcat`. Record the working spelling.

- [ ] **Step 3: Probe array(float32) ORDER BY pattern**

```bash
echo "SELECT cosine_distance(cast([1.0,0.0], 'array(float32)'), [0.5,0.5]) AS d" | run_sql
```

Expected: a numeric result (~0.293). Confirms float32 arrays work with the function.

---

### Task 2: Update `manifest.yaml`

**Files:**
- Modify: `apps/hacker-news/manifest.yaml`

- [ ] **Step 1: Bump version**

Change `version: 1.0.0` → `version: 1.1.0`.

- [ ] **Step 2: Append config keys**

Add to the end of the `config:` list:

```yaml
  - key: llm_base_url
    type: string
    required: false
    default: "https://api.openai.com/v1"
    description: Base URL of the OpenAI-compatible API used for embeddings and chat
  - key: llm_api_key
    type: string
    required: true
    description: API key for the OpenAI-compatible endpoint
  - key: embedding_model
    type: string
    required: false
    default: "text-embedding-3-small"
    description: Embedding model used to vectorize stories and questions
  - key: chat_model
    type: string
    required: false
    default: "gpt-4o-mini"
    description: Chat model used to answer questions
```

- [ ] **Step 3: Append resources (order matters — UDF before the MV that calls it)**

Add to the end of the `resources:` list:

```yaml
  - file: ddl/004_udf_embed_text.sql
    type: udf
    name: embed_text
  - file: ddl/005_hn_story.sql
    type: stream
    name: hn_story
  - file: ddl/006_mv_hn_story_embedding.sql
    type: materialized_view
    name: mv_hn_story_embedding
  - file: ddl/007_udf_rag_answer.sql
    type: udf
    name: rag_answer
```

- [ ] **Step 4: Validate YAML parses**

```bash
python3 -c "import yaml,sys; d=yaml.safe_load(open('apps/hacker-news/manifest.yaml')); print(d['version'], len(d['resources']), len(d['config']))"
```

Expected: `1.1.0 7 11`

- [ ] **Step 5: Commit**

```bash
git add apps/hacker-news/manifest.yaml
git commit -m "hn: manifest config + resources for RAG feature"
```

---

### Task 3: Embedding UDF — `ddl/004_udf_embed_text.sql`

**Files:**
- Create: `apps/hacker-news/ddl/004_udf_embed_text.sql`

- [ ] **Step 1: Write the file** (one statement; `CREATE OR REPLACE` keeps installs idempotent)

```sql
CREATE OR REPLACE FUNCTION embed_text(input string) RETURNS array(float32)
LANGUAGE PYTHON AS
$$
import requests
import time

def embed_text(inputs):
    base_url = '{{ .Config.llm_base_url }}'.rstrip('/')
    api_key = '{{ .Config.llm_api_key }}'
    model = '{{ .Config.embedding_model }}'
    out = [[] for _ in inputs]

    todo = [i for i, t in enumerate(inputs) if t and t.strip()]
    if not todo:
        return out

    s = requests.Session()
    s.headers.update({
        'Authorization': 'Bearer ' + api_key,
        'Content-Type': 'application/json',
    })

    for chunk_start in range(0, len(todo), 100):
        chunk = todo[chunk_start:chunk_start + 100]
        texts = [inputs[i][:2000] for i in chunk]
        for attempt in range(3):
            try:
                r = s.post(base_url + '/embeddings',
                           json={'model': model, 'input': texts},
                           timeout=(5, 30))
                r.raise_for_status()
                for j, item in enumerate(r.json()['data']):
                    out[chunk[item.get('index', j)]] = item['embedding']
                break
            except Exception:
                if attempt == 2:
                    break
                time.sleep(0.5 * (2 ** attempt))
    return out
$$;
```

Key behaviors: vectorized batch call (≤100 inputs per request), 2,000-char truncation, empty input → `[]` with no API call, 3 retries with backoff, returns `[]` on persistent failure (never raises — the MV must not stall).

- [ ] **Step 2: Test the rendered SQL against the live instance**

Render the template with test values and execute (uses the real key so the call path is verified):

```bash
sed -e "s|{{ .Config.llm_base_url }}|https://api.openai.com/v1|" \
    -e "s|{{ .Config.llm_api_key }}|$LLM_API_KEY|" \
    -e "s|{{ .Config.embedding_model }}|text-embedding-3-small|" \
    apps/hacker-news/ddl/004_udf_embed_text.sql | run_sql
echo "SELECT length(embed_text('hello world')) AS dims, length(embed_text('')) AS empty_dims" | run_sql
```

Expected: first command silent (200 OK); second returns `{"dims":1536,"empty_dims":0}`.

- [ ] **Step 3: Drop the test UDF** (install will recreate it inside the `hn` db context)

```bash
echo "DROP FUNCTION IF EXISTS embed_text" | run_sql
```

- [ ] **Step 4: Commit**

```bash
git add apps/hacker-news/ddl/004_udf_embed_text.sql
git commit -m "hn: embed_text UDF (OpenAI-compatible embeddings)"
```

---

### Task 4: Vector-store stream — `ddl/005_hn_story.sql`

**Files:**
- Create: `apps/hacker-news/ddl/005_hn_story.sql`

- [ ] **Step 1: Write the file**

```sql
CREATE STREAM IF NOT EXISTS {{ .DB }}.hn_story (
  id uint64,
  title string,
  text string,
  url string,
  by string,
  score uint32,
  time datetime,
  embedding array(float32)
)
TTL to_datetime(_tp_time) + INTERVAL {{ .Config.stream_ttl_days }} DAY
SETTINGS logstore_retention_bytes = '{{ .Config.logstore_retention_bytes }}', logstore_retention_ms = '{{ .Config.logstore_retention_ms }}';
```

- [ ] **Step 2: Test the rendered SQL**

```bash
sed -e "s|{{ .DB }}|default|" \
    -e "s|{{ .Config.stream_ttl_days }}|7|" \
    -e "s|{{ .Config.logstore_retention_bytes }}|107374182|" \
    -e "s|{{ .Config.logstore_retention_ms }}|300000|" \
    apps/hacker-news/ddl/005_hn_story.sql | run_sql
echo "DESCRIBE default.hn_story" | run_sql
echo "DROP STREAM IF EXISTS default.hn_story" | run_sql
```

Expected: DESCRIBE lists all 8 columns with `embedding` as `array(float32)`; no errors.

- [ ] **Step 3: Commit**

```bash
git add apps/hacker-news/ddl/005_hn_story.sql
git commit -m "hn: hn_story vector-store stream"
```

---

### Task 5: Embedding MV — `ddl/006_mv_hn_story_embedding.sql`

**Files:**
- Create: `apps/hacker-news/ddl/006_mv_hn_story_embedding.sql`

- [ ] **Step 1: Write the file**

```sql
CREATE MATERIALIZED VIEW IF NOT EXISTS {{ .DB }}.mv_hn_story_embedding
INTO {{ .DB }}.hn_story AS
SELECT
  to_uint64_or_zero(message:id) AS id,
  message:title AS title,
  message:text AS text,
  message:url AS url,
  message:by AS by,
  to_uint32_or_zero(message:score) AS score,
  to_datetime(to_int64_or_zero(message:time)) AS time,
  embed_text(concat(message:title, ' ', message:text)) AS embedding
FROM {{ .DB }}.hn_post
WHERE message:type = 'story' AND message:title != '' AND message:deleted != 'true' AND message:dead != 'true';
```

Note: `embed_text` is called on the raw JSON extracts (not the aliases) to avoid alias-resolution surprises.

- [ ] **Step 2: Verify the SELECT shape compiles against the live instance**

The MV itself needs `hn_post` + the UDF + `hn_story`, all of which exist together only after install, so here only validate the extraction logic with `EXPLAIN`-style execution against the installed `hn.hn_post` if present, otherwise skip to commit:

```bash
echo "SELECT to_uint64_or_zero(message:id) AS id, message:title AS title, to_datetime(to_int64_or_zero(message:time)) AS time FROM table(hn.hn_post) WHERE message:type = 'story' LIMIT 3" | run_sql
```

Expected: rows with numeric `id`, non-empty `title`, sane `time` (or empty result if the old app isn't installed — that's fine, full verification happens in Task 7).

- [ ] **Step 3: Commit**

```bash
git add apps/hacker-news/ddl/006_mv_hn_story_embedding.sql
git commit -m "hn: MV embedding stories into hn_story"
```

---

### Task 6: Answer UDF — `ddl/007_udf_rag_answer.sql`

**Files:**
- Create: `apps/hacker-news/ddl/007_udf_rag_answer.sql`

- [ ] **Step 1: Write the file**

```sql
CREATE OR REPLACE FUNCTION rag_answer(question string, context string) RETURNS string
LANGUAGE PYTHON AS
$$
import requests

SYSTEM_PROMPT = (
    'You answer questions about recent Hacker News posts. '
    'Use ONLY the posts provided in the context. Cite the titles of the stories you used. '
    'If the context is empty or does not cover the question, say that no relevant posts were found.'
)

def rag_answer(questions, contexts):
    base_url = '{{ .Config.llm_base_url }}'.rstrip('/')
    api_key = '{{ .Config.llm_api_key }}'
    model = '{{ .Config.chat_model }}'
    out = []
    s = requests.Session()
    s.headers.update({
        'Authorization': 'Bearer ' + api_key,
        'Content-Type': 'application/json',
    })
    for q, ctx in zip(questions, contexts):
        try:
            r = s.post(base_url + '/chat/completions', json={
                'model': model,
                'messages': [
                    {'role': 'system', 'content': SYSTEM_PROMPT},
                    {'role': 'user', 'content': 'Context posts:\n' + ctx + '\n\nQuestion: ' + q},
                ],
                'temperature': 0.2,
            }, timeout=(5, 60))
            r.raise_for_status()
            out.append(r.json()['choices'][0]['message']['content'])
        except Exception as e:
            out.append('LLM error: ' + str(e))
    return out
$$;
```

- [ ] **Step 2: Test the rendered SQL**

```bash
sed -e "s|{{ .Config.llm_base_url }}|https://api.openai.com/v1|" \
    -e "s|{{ .Config.llm_api_key }}|$LLM_API_KEY|" \
    -e "s|{{ .Config.chat_model }}|gpt-4o-mini|" \
    apps/hacker-news/ddl/007_udf_rag_answer.sql | run_sql
echo "SELECT rag_answer('What does the post say?', 'Title: Test Post\nBy: alice\nText: Timeplus ships vector search.') AS answer" | run_sql
echo "DROP FUNCTION IF EXISTS rag_answer" | run_sql
```

Expected: a JSON row whose `answer` mentions the test post / vector search; then clean drop.

- [ ] **Step 3: Commit**

```bash
git add apps/hacker-news/ddl/007_udf_rag_answer.sql
git commit -m "hn: rag_answer UDF (OpenAI-compatible chat)"
```

---

### Task 7: Build, install, verify the pipeline end-to-end

**Files:** none (build + runtime verification)

- [ ] **Step 1: Check for an existing install and remove it**

```bash
curl -s http://localhost:8000/default/api/v1beta2/apps | python3 -m json.tool | head -50
```

If `io.timeplus.hacker-news` is listed, uninstall (adjust to the id/endpoint shape the list response shows):

```bash
curl -s -X DELETE "http://localhost:8000/default/api/v1beta2/apps/io.timeplus.hacker-news"
```

- [ ] **Step 2: Build**

```bash
cd apps/hacker-news && rm -f hacker-news.tpapp && make build && cd ../..
unzip -l apps/hacker-news/hacker-news.tpapp
```

Expected: archive lists `manifest.yaml`, 7 ddl files, `dashboards/` (dashboard added in Task 8 — rebuild happens there; this validates packaging early).

- [ ] **Step 3: Install with config**

```bash
curl -s -X POST http://localhost:8000/default/api/v1beta2/apps/install \
  -F "file=@apps/hacker-news/hacker-news.tpapp" \
  -F "config[llm_api_key]=$LLM_API_KEY"
```

Expected: success response, no `provision <name>` error. (Reminder: only the `config[key]=value` bracket form works.)

- [ ] **Step 4: Verify python packages and resources**

```bash
echo "SELECT name, status FROM system.python_packages" | run_sql
echo "SHOW STREAMS FROM hn" | run_sql
```

Expected: `requests` → `installed`; streams include `hn_post`, `hn_story`, MV `mv_hn_story_embedding`.

- [ ] **Step 5: Watch `hn_story` fill (task runs every 10s; HN posts a few stories/minute — wait up to ~3 min)**

```bash
sleep 90
echo "SELECT count() AS rows, count_if(length(embedding) > 0) AS embedded FROM table(hn.hn_story)" | run_sql
```

Expected: `rows ≥ 1` and `embedded ≥ 1`. If `rows > 0` but `embedded = 0`, the embeddings API is failing — debug the UDF (check key, base URL) before proceeding.

- [ ] **Step 6: Run the full RAG query** (substitute the function spellings recorded in Task 1 if different)

```bash
echo "WITH embed_text('What programming languages are people discussing?') AS qvec,
hits AS (
  SELECT title, url, by, score, left(text, 500) AS snippet,
         cosine_distance(embedding, qvec) AS dist
  FROM table(hn.hn_story)
  WHERE length(embedding) > 0
  ORDER BY dist ASC
  LIMIT 5
)
SELECT rag_answer('What programming languages are people discussing?',
  array_string_concat(group_array(concat('Title: ', title, '\nBy: ', by, '\nURL: ', url, '\nText: ', snippet)), '\n---\n')) AS answer
FROM hits" | run_sql
```

Expected: a grounded answer string citing actual story titles (or "no relevant posts" if the corpus is still tiny). NOT `LLM error: …`.

- [ ] **Step 7: Commit nothing — this task only verifies.** If fixes were needed, amend the relevant file and re-run from Step 1 of this task.

---

### Task 8: Q&A dashboard — `dashboards/main.json`

**Files:**
- Create: `apps/hacker-news/dashboards/main.json`

Conventions that are easy to get wrong (from project memory): 12-column grid; text input is `chartType: "text"` with `inlineValues: ""`; single-value panels are `chartType: "singleValue"` with a full `config` block; `labelWidth` is a percentage; multi-series line charts need `color`; dashboard Go-templates use `[[ ]]`, frontend filter variables use `{{ }}`.

- [ ] **Step 1: Write the file**

```json
[
  {
    "id": "hn-control-question",
    "title": "Ask Hacker News",
    "description": "",
    "position": { "h": 1, "w": 12, "x": 0, "y": 0, "nextX": 12, "nextY": 1 },
    "viz_type": "control",
    "viz_content": "",
    "viz_config": {
      "chartType": "text",
      "defaultValue": "What is happening with AI?",
      "inlineValues": "",
      "label": "Question",
      "labelWidth": "10",
      "target": "filter_question"
    }
  },
  {
    "id": "hn-rag-answer",
    "title": "AI Answer",
    "description": "Embeds the question, retrieves the 5 most similar stories by cosine distance, and asks the LLM to answer from them.",
    "position": { "h": 5, "w": 8, "x": 0, "y": 1, "nextX": 8, "nextY": 6 },
    "viz_type": "chart",
    "viz_content": "WITH embed_text('{{filter_question}}') AS qvec, hits AS (SELECT title, url, by, score, left(text, 500) AS snippet, cosine_distance(embedding, qvec) AS dist FROM table([[ .DB ]].hn_story) WHERE length(embedding) > 0 ORDER BY dist ASC LIMIT 5) SELECT rag_answer('{{filter_question}}', array_string_concat(group_array(concat('Title: ', title, '\\nBy: ', by, '\\nURL: ', url, '\\nText: ', snippet)), '\\n---\\n')) AS answer FROM hits",
    "viz_config": {
      "chartType": "table"
    }
  },
  {
    "id": "hn-stories-embedded",
    "title": "Stories Embedded",
    "description": "Stories in the vector store with a non-empty embedding.",
    "position": { "h": 2, "w": 4, "x": 8, "y": 1, "nextX": 12, "nextY": 3 },
    "viz_type": "chart",
    "viz_content": "SELECT count() AS embedded FROM table([[ .DB ]].hn_story) WHERE length(embedding) > 0",
    "viz_config": {
      "chartType": "singleValue",
      "config": {
        "value": "embedded",
        "sparkline": false,
        "delta": false,
        "unit": { "value": "", "position": "right" },
        "color": "blue",
        "sparklineColor": "blue",
        "increaseColor": "green",
        "decreaseColor": "red",
        "fractionDigits": 0,
        "fontSize": 48
      }
    }
  },
  {
    "id": "hn-stories-per-hour",
    "title": "Stories per Hour (24h)",
    "description": "",
    "position": { "h": 3, "w": 4, "x": 8, "y": 3, "nextX": 12, "nextY": 6 },
    "viz_type": "chart",
    "viz_content": "SELECT to_start_of_hour(time) AS hour, count() AS stories FROM table([[ .DB ]].hn_story) WHERE time > now() - INTERVAL 24 HOUR GROUP BY hour ORDER BY hour",
    "viz_config": {
      "chartType": "bar",
      "config": {
        "xAxis": "hour",
        "yAxis": "stories",
        "color": "",
        "xRange": "Infinity",
        "xFormat": "",
        "xTitle": "",
        "yTitle": "",
        "yRange": { "min": null, "max": null },
        "dataLabel": false,
        "showAll": false,
        "legend": false,
        "gridlines": true,
        "unit": { "position": "left", "value": "" },
        "fractionDigits": 0,
        "colors": ["#D53F8C"],
        "yTickLabel": { "maxChar": 25 }
      }
    }
  },
  {
    "id": "hn-retrieved-stories",
    "title": "Retrieved Stories (top-5 by similarity)",
    "description": "The stories the answer above is based on. Lower distance = more similar.",
    "position": { "h": 4, "w": 12, "x": 0, "y": 6, "nextX": 12, "nextY": 10 },
    "viz_type": "chart",
    "viz_content": "WITH embed_text('{{filter_question}}') AS qvec SELECT title, by, score, url, round(cosine_distance(embedding, qvec), 4) AS distance FROM table([[ .DB ]].hn_story) WHERE length(embedding) > 0 ORDER BY distance ASC LIMIT 5",
    "viz_config": {
      "chartType": "table"
    }
  },
  {
    "id": "hn-latest-stories",
    "title": "Latest Stories",
    "description": "Most recent stories ingested into the vector store.",
    "position": { "h": 4, "w": 12, "x": 0, "y": 10, "nextX": 12, "nextY": 14 },
    "viz_type": "chart",
    "viz_content": "SELECT time, title, by, score, url FROM table([[ .DB ]].hn_story) ORDER BY time DESC LIMIT 20",
    "viz_config": {
      "chartType": "table"
    }
  }
]
```

- [ ] **Step 2: Validate JSON and live-validate every panel query**

```bash
python3 -m json.tool apps/hacker-news/dashboards/main.json > /dev/null && echo JSON_OK
```

Then execute each `viz_content` with `[[ .DB ]]` → `hn` and `{{filter_question}}` → `What is happening with AI?` substituted (and `\\n` → `\n`):

```bash
python3 - <<'EOF'
import json, subprocess
panels = json.load(open('apps/hacker-news/dashboards/main.json'))
for p in panels:
    q = p['viz_content']
    if not q or p['viz_type'] == 'control':
        continue
    q = q.replace('[[ .DB ]]', 'hn').replace('{{filter_question}}', 'What is happening with AI?')
    r = subprocess.run(['curl', '-s', '-w', '\n%{http_code}', 'http://localhost:8123/?default_format=JSONEachRow',
                        '-u', 'default:', '--data-binary', q], capture_output=True, text=True)
    body, code = r.stdout.rsplit('\n', 1)
    print(p['id'], '->', code, body[:120].replace('\n', ' | '))
    assert code == '200', f"panel {p['id']} failed: {body}"
print('ALL PANELS OK')
EOF
```

Expected: every panel prints `200` and plausible rows; `ALL PANELS OK`.

- [ ] **Step 3: Rebuild, reinstall, eyeball the dashboard**

```bash
cd apps/hacker-news && make build && cd ../..
curl -s -X DELETE "http://localhost:8000/default/api/v1beta2/apps/io.timeplus.hacker-news"
curl -s -X POST http://localhost:8000/default/api/v1beta2/apps/install \
  -F "file=@apps/hacker-news/hacker-news.tpapp" \
  -F "config[llm_api_key]=$LLM_API_KEY"
```

Ask the user to open the dashboard in the console and confirm panels render (especially the singleValue and bar panels — per project memory, `viz_config` fields must be validated against the rendered panel, not just the query).

- [ ] **Step 4: Commit**

```bash
git add apps/hacker-news/dashboards/main.json
git commit -m "hn: RAG Q&A dashboard"
```

---

### Task 9: README

**Files:**
- Create: `apps/hacker-news/README.md`

- [ ] **Step 1: Write the file**

```markdown
# Hacker News Live Feed + RAG Q&A

Ingests Hacker News posts via the official Firebase API into Timeplus, embeds
every story with an OpenAI-compatible embeddings API, and answers natural-language
questions over the live corpus with vector search + an LLM — all in SQL.

## Pipeline

    get_hn_post (task, every 10s)
      └── hn_post (raw JSON stream)
            └── mv_hn_story_embedding  (MV: stories only → embed_text UDF)
                  └── hn_story  (id, title, text, url, by, score, time,
                                 embedding array(float32))

    Q&A: embed_text(question) → cosine_distance top-5 over table(hn_story)
         → context string → rag_answer(question, context) → answer

## Install

Requires a running Timeplus instance and an OpenAI-compatible API key.

    make build
    curl -X POST http://localhost:8000/default/api/v1beta2/apps/install \
      -F "file=@hacker-news.tpapp" \
      -F "config[llm_api_key]=sk-..."

Optional config keys: `llm_base_url` (default `https://api.openai.com/v1`),
`embedding_model` (default `text-embedding-3-small`), `chat_model`
(default `gpt-4o-mini`) — so Ollama / vLLM / LM Studio endpoints work too.

## Ask a question in SQL

    WITH embed_text('What is happening with AI?') AS qvec,
    hits AS (
      SELECT title, url, by, score, left(text, 500) AS snippet,
             cosine_distance(embedding, qvec) AS dist
      FROM table(hn.hn_story)
      WHERE length(embedding) > 0
      ORDER BY dist ASC
      LIMIT 5
    )
    SELECT rag_answer('What is happening with AI?',
      array_string_concat(group_array(concat('Title: ', title, '\nBy: ', by,
        '\nURL: ', url, '\nText: ', snippet)), '\n---\n')) AS answer
    FROM hits;

Note: single quotes in the question must be escaped (`''`).

## Dashboard

The bundled dashboard has a question input wired to the RAG query, the
retrieved top-5 stories with similarity scores, and pipeline-health panels
(stories embedded, stories/hour, latest stories).

## Troubleshooting

- `SELECT * FROM system.python_packages` — `requests` must be `installed`.
- `embedded = 0` while `rows > 0` in `hn_story` → embeddings API failing
  (bad key / base URL); rows ingested during an outage stay unsearchable.
- `LLM error: …` in the answer → chat API failing; the error text is the body.
```

- [ ] **Step 2: Commit**

```bash
git add apps/hacker-news/README.md
git commit -m "hn: README for RAG feature"
```

---

### Task 10: Final verification sweep

- [ ] **Step 1: Re-run the end-to-end checks** (Task 7 Steps 4–6) once more after the final install.
- [ ] **Step 2: Confirm the working tree is clean and all commits are present**

```bash
git status --short && git log --oneline main..HEAD
```

Expected: clean tree; commits for spec, manifest, 4 DDL files, dashboard, README.
