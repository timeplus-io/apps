FROM python:3.12-slim

WORKDIR /workspace

COPY registry/requirements.txt registry/
RUN pip install --no-cache-dir -r registry/requirements.txt

COPY apps/ apps/
COPY registry/ registry/

EXPOSE 9090

CMD ["python3", "registry/server.py"]
