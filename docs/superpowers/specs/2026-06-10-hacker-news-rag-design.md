# Hacker News RAG Q&A — Design

**Date:** 2026-06-10
**App:** `apps/hacker-news` (`io.timeplus.hacker-news`, db `hn`)
**Goal:** Demo an AI question-answering (RAG) system over the live Hacker News feed, built entirely from Timeplus primitives: Python UDFs, a materialized view, and ClickHouse-style vector search in SQL.

## Overview

The existing app ingests raw HN items (JSON in `hn_post.message`) via a scheduled task. This feature adds:

1. An **embedding UDF** (`embed_text`) calling an OpenAI-compatible embeddings API.
2. A **vector store**: an MV filters stories out of `hn_post`, embeds them, and writes them with an `embedding array(float32)` column to a new `hn_story` stream.
3. An **answer UDF** (`rag_answer`) calling an OpenAI-compatible chat-completions API.
4. A **one-statement RAG query**: embed the question, brute-force cosine search over `table(hn_story)` for top-k stories, assemble a context string in SQL, pass question + context to `rag_answer`.
5. A **Q&A dashboard** with a question text input, answer panel, retrieved-stories panel, and pipeline-health panels.

## Architecture

```
hn_post (existing raw JSON stream, task-fed every 10s)
  └── mv_hn_story_embedding   MV: WHERE type='story' AND title != '' AND NOT deleted/dead
        │                      parses JSON fields, calls embed_text(title + ' ' + text)
        └── hn_story           id, title, text, url, by, score, posted_at,
                               embedding array(float32) — TTL = stream_ttl_days

Q&A (ad-hoc SQL / dashboard panel):
  embed_text(question)
    → SELECT … cosine_distance(embedding, qvec) AS dist
      FROM table(hn_story) WHERE length(embedding) > 0
      ORDER BY dist ASC LIMIT k
    → group_array(formatted hit) joined into one context string
    → rag_answer(question, context)
```

Brute-force scan is intentional: a 7-day HN story corpus is tens of thousands of rows; no vector index needed. This mirrors the standard ClickHouse vector-search pattern.

## Components

### `004_udf_embed_text.sql` — embedding UDF

- `CREATE OR REPLACE FUNCTION embed_text(input string) RETURNS array(float32) LANGUAGE PYTHON`.
- Vectorized: receives a list of texts per batch; sends one `POST {{llm_base_url}}/embeddings` request per chunk of ≤100 inputs, model `{{embedding_model}}`.
- Truncates each input to ~2,000 chars before sending.
- Empty/whitespace-only input → `[]` without an API call.
- Retries 3× with exponential backoff on timeout/HTTP error; on persistent failure returns `[]` for the affected rows. Never raises — the MV must not stall.
- Config values are baked into the UDF source at install time via Go-template variables.

### `005_hn_story.sql` — vector store stream

Append stream `{{ .DB }}.hn_story`:

| column | type |
|---|---|
| `id` | `uint64` |
| `title` | `string` |
| `text` | `string` |
| `url` | `string` |
| `by` | `string` |
| `score` | `uint32` |
| `posted_at` | `datetime` (from HN unix seconds) |
| `embedding` | `array(float32)` |

TTL `to_datetime(_tp_time) + INTERVAL {{ .Config.stream_ttl_days }} DAY`, same logstore retention settings pattern as `hn_post`.

### `006_mv_hn_story_embedding.sql` — embedding MV

`CREATE MATERIALIZED VIEW IF NOT EXISTS {{ .DB }}.mv_hn_story_embedding INTO {{ .DB }}.hn_story AS SELECT … FROM {{ .DB }}.hn_post WHERE message:type = 'story' AND message:title != '' AND message:deleted != 'true' AND message:dead != 'true'`, extracting the JSON fields and computing `embed_text(concat(title, ' ', text)) AS embedding`.

### `007_udf_rag_answer.sql` — answer UDF

- `CREATE OR REPLACE FUNCTION rag_answer(question string, context string) RETURNS string LANGUAGE PYTHON`.
- Calls `POST {{llm_base_url}}/chat/completions`, model `{{chat_model}}`.
- System prompt: answer using only the provided Hacker News posts; cite story titles; say so when the context doesn't cover the question.
- Vectorized loop per row (normally one row). On API error returns `"LLM error: …"` as the answer string — never raises.

### The RAG query (documented in README, used in the dashboard)

```sql
WITH
  'What is happening with AI agents?' AS question,
  embed_text(question) AS qvec,
  hits AS (
    SELECT title, url, by, score, left(text, 500) AS snippet,
           cosine_distance(embedding, qvec) AS dist
    FROM table(hn.hn_story)
    WHERE length(embedding) > 0
    ORDER BY dist ASC
    LIMIT 5
  )
SELECT rag_answer(question, array_string_concat(group_array(
  concat('Title: ', title, '\nBy: ', by, '\nURL: ', url, '\n', snippet)
), '\n---\n')) AS answer
FROM hits;
```

Exact function names (`cosine_distance`, `array_string_concat`) are verified live at install time; the implementation adjusts if Timeplus names differ.

### Manifest changes

- `version` → `1.1.0`.
- New config keys (templated into UDF source):
  - `llm_base_url` — string, default `https://api.openai.com/v1`
  - `llm_api_key` — string, required, no default
  - `embedding_model` — string, default `text-embedding-3-small`
  - `chat_model` — string, default `gpt-4o-mini`
- New resources appended in order: `embed_text` (udf), `hn_story` (stream), `mv_hn_story_embedding` (materialized_view), `rag_answer` (udf).
- `requests` already listed in `python_packages`; no additions.
- Install command passes the key as a `config[llm_api_key]=…` multipart field.

### Dashboard — `dashboards/main.json` (new; the app has none today)

12-column grid. Panels:

1. **Question input** — text control (`chartType: "text"`), variable consumed by the two RAG panels, default question pre-filled.
2. **Answer** — table panel running the full RAG statement with the question variable substituted.
3. **Retrieved stories** — table of top-k titles/URL/author/score/similarity for the same question.
4. **Pipeline health** — single-value panel (`chartType: "singleValue"`): stories embedded (count over `table(hn_story)` where embedding non-empty); line panel: stories per hour; table: latest stories.

Every panel is live-validated against a running instance before commit (per project conventions: filter on the right time column, no cargo-culted `viz_config` fields).

### README

New `apps/hacker-news/README.md`: pipeline diagram, install command including `config[llm_api_key]`, the RAG demo query, dashboard description, troubleshooting (package install status, embedding failures).

## Error handling

| Failure | Behavior |
|---|---|
| Embeddings API down | UDF retries, then returns `[]`; rows stored unsearchable; MV keeps flowing |
| Chat API down | `rag_answer` returns `"LLM error: …"` string; visible in panel |
| Empty corpus / no hits | Context string empty; LLM instructed to say it has no relevant posts |
| Empty question | `embed_text` returns `[]` without an API call; query returns no hits |

## Out of scope

- Comments in the corpus (stories only).
- Vector indexes / ANN — brute force only.
- Re-embedding rows that failed embedding.
- A streaming question/answer pipeline (ad-hoc SQL only).

## Testing

1. `make build APP=hacker-news` packages cleanly.
2. `make install` with real `llm_api_key` against local Timeplus.
3. `system.python_packages` shows `requests` installed.
4. `hn_story` fills with non-empty embeddings within ~1 min of install.
5. The RAG query returns a grounded answer citing real story titles.
6. Each dashboard panel renders correctly (live validation).
