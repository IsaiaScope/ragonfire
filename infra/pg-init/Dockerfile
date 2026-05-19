FROM alpine:3.20
RUN apk add --no-cache util-linux e2fsprogs coreutils
COPY mount-loop.sh /usr/local/bin/mount-loop.sh
RUN chmod +x /usr/local/bin/mount-loop.sh
ENTRYPOINT ["/usr/local/bin/mount-loop.sh"]
