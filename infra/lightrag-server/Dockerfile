FROM python:3.12-slim@sha256:9d3abd9fc11d06998ccdbdd93b4dd49b5ad7d67fcbbc11c016eb0eb2c2194891

ARG LIGHTRAG_VERSION=1.4.5
RUN apt-get update && apt-get install -y --no-install-recommends \
    curl ca-certificates \
 && rm -rf /var/lib/apt/lists/*

RUN pip install --no-cache-dir \
    "lightrag-hku[api]==${LIGHTRAG_VERSION}" \
    "asyncpg==0.30.0" \
    "psycopg[binary]==3.2.3" \
    "pgvector==0.4.1" \
    "ollama==0.4.7" \
    "python-dotenv==1.0.1"

EXPOSE 9621
CMD ["sh", "-c", "mkdir -p \"${LOG_DIR:-/tmp/lightrag/logs}\" && exec lightrag-server"]
