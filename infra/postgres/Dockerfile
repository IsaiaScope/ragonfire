FROM pgvector/pgvector:pg16@sha256:00ba258a66dac104fd5171074a0084462a64a1369d8513f3d0a634e2f24d15bc
ARG AGE_REF=0048900f372d4dfd5c236f78b8a8453bcdbb458e
RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential git postgresql-server-dev-16 flex bison ca-certificates \
    util-linux e2fsprogs \
 && mkdir /tmp/age \
 && cd /tmp/age \
 && git init \
 && git remote add origin https://github.com/apache/age.git \
 && git fetch --depth 1 origin ${AGE_REF} \
 && git checkout FETCH_HEAD \
 && cd /tmp/age && make install \
 && rm -rf /tmp/age \
 && apt-get purge -y build-essential git flex bison postgresql-server-dev-16 \
 && apt-get autoremove -y && rm -rf /var/lib/apt/lists/*

COPY entrypoint-loop.sh /usr/local/bin/entrypoint-loop.sh
RUN chmod +x /usr/local/bin/entrypoint-loop.sh
ENTRYPOINT ["/usr/local/bin/entrypoint-loop.sh"]
CMD ["postgres"]
