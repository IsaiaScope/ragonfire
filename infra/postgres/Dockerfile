FROM pgvector/pgvector:pg16
ARG AGE_VERSION=PG16/v1.5.0-rc0
RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential git postgresql-server-dev-16 flex bison ca-certificates \
    util-linux e2fsprogs \
 && git clone --depth 1 --branch ${AGE_VERSION} https://github.com/apache/age.git /tmp/age \
 && cd /tmp/age && make install \
 && rm -rf /tmp/age \
 && apt-get purge -y build-essential git flex bison postgresql-server-dev-16 \
 && apt-get autoremove -y && rm -rf /var/lib/apt/lists/*

COPY entrypoint-loop.sh /usr/local/bin/entrypoint-loop.sh
RUN chmod +x /usr/local/bin/entrypoint-loop.sh
ENTRYPOINT ["/usr/local/bin/entrypoint-loop.sh"]
CMD ["postgres"]
