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
