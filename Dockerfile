FROM python:3.12-slim

RUN apt-get update && apt-get install -y --no-install-recommends make zip && rm -rf /var/lib/apt/lists/*

WORKDIR /workspace

COPY registry/requirements.txt registry/
RUN pip install --no-cache-dir -r registry/requirements.txt

COPY apps/ apps/
COPY registry/ registry/
COPY Makefile .

RUN make build-all && python3 registry/build.py

EXPOSE 9090

CMD ["python3", "registry/server.py"]
