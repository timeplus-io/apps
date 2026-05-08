CREATE EXTERNAL STREAM IF NOT EXISTS {{ .DB }}.github_events_stream(
    id string,
    created_at string,
    actor string,
    type string,
    repo string,
    payload string
)
AS $$
import time
from github import Github, GithubException

token = '{{ .Config.github_token }}'
g = Github(token, per_page=100) if token else None
known_ids = set()

def read_github():
    global g, known_ids
    if g is None:
        return

    while True:
        try:
            events = g.get_events()
            for e in events:
                if e.id not in known_ids:
                    known_ids.add(e.id)
                    yield (
                        str(e.id),
                        e.created_at.isoformat(),
                        str(e.actor.login),
                        str(e.type),
                        str(e.repo.name),
                        str(e.payload)
                    )

            if len(known_ids) > 5000:
                known_ids.clear()

            time.sleep(2)

        except GithubException:
            time.sleep(600)
        except Exception:
            time.sleep(10)
$$
SETTINGS
    type = 'python',
    read_function_name = 'read_github'
