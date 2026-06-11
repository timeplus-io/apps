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
        # Timeplus passes string UDF args to Python as bytes — decode before use.
        if isinstance(q, bytes):
            q = q.decode('utf-8')
        if isinstance(ctx, bytes):
            ctx = ctx.decode('utf-8')
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
            choices = r.json().get('choices', [])
            content = choices[0]['message'].get('content') if choices else None
            out.append(content if content else 'LLM error: empty response from model')
        except Exception as e:
            out.append('LLM error: ' + str(e))
    return out
$$;
