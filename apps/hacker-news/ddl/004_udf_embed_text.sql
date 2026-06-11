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
        # Timeplus passes string UDF args to Python as bytes — decode before JSON-serializing.
        texts = [(inputs[i].decode('utf-8') if isinstance(inputs[i], bytes) else inputs[i])[:2000] for i in chunk]
        for attempt in range(3):
            try:
                r = s.post(base_url + '/embeddings',
                           json={'model': model, 'input': texts},
                           timeout=(5, 30))
                r.raise_for_status()
                for j, item in enumerate(r.json()['data']):
                    out[chunk[item.get('index', j)]] = item['embedding']
                break
            except Exception as e:
                if attempt == 2:
                    print('embed_text: chunk failed after retries: %s' % e)
                    break
                time.sleep(0.5 * (2 ** attempt))
    return out
$$;
