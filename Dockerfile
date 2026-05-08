FROM python:3.12-slim AS builder

WORKDIR /workspace

COPY registry/requirements.txt registry/
RUN pip install --no-cache-dir -r registry/requirements.txt

COPY apps/ apps/
COPY registry/build.py registry/

ARG BASE_URL=http://localhost:9090
ENV BASE_URL=${BASE_URL}

RUN python3 registry/build.py

# ---

FROM nginx:alpine

COPY --from=builder /workspace/registry /usr/share/nginx/html

EXPOSE 80
