CREATE OR REPLACE FUNCTION get_hn_posts_after_id_with_retry(start_id uint64, lookbacks uint64, limits uint64) RETURNS array(string)
LANGUAGE PYTHON AS
$$
import requests
import json
import time

def get_hn_posts_after_id_with_retry(starts, lookbacks, limits):
    s = requests.Session()
    s.headers.update({'User-Agent': 'timeplus-udf/1.0'})
    out = []

    def fetch_with_retry(url, max_retries=3, backoff=0.5):
        for attempt in range(max_retries):
            try:
                return s.get(url, timeout=(5, 5))
            except requests.exceptions.Timeout:
                if attempt == max_retries - 1:
                    raise
                time.sleep(backoff * (2 ** attempt))
            except requests.exceptions.RequestException:
                if attempt == max_retries - 1:
                    raise
                time.sleep(backoff)
        return None

    for start_id, lookback, limit in zip(starts, lookbacks, limits):
        posts = []
        try:
            time.sleep(0.1)
            r = fetch_with_retry('https://hacker-news.firebaseio.com/v0/maxitem.json')
            max_id = int(r.json())

            if start_id == 0:
                start_id = max_id - lookback

            total = int(min(max_id - start_id, limit))

            for item_id in range(start_id + 1, start_id + total + 1):
                try:
                    r = fetch_with_retry(
                        f'https://hacker-news.firebaseio.com/v0/item/{item_id}.json'
                    )
                    item = r.json()
                    if item:
                        posts.append(json.dumps({
                            'id': item.get('id'),
                            'type': item.get('type', ''),
                            'by': item.get('by', ''),
                            'time': item.get('time', 0),
                            'title': item.get('title', ''),
                            'text': item.get('text', ''),
                            'url': item.get('url', ''),
                            'score': item.get('score', 0),
                            'descendants': item.get('descendants', 0),
                            'parent': item.get('parent'),
                            'kids': item.get('kids', []),
                            'deleted': item.get('deleted', False),
                            'dead': item.get('dead', False),
                            'poll': item.get('poll'),
                            'parts': item.get('parts', []),
                        }))
                except Exception as e:
                    posts.append(json.dumps({'error': str(e)}))

        except Exception as e:
            posts.append(json.dumps({'error': str(e)}))

        out.append(posts)

    return out
$$;
