FROM alpine:3.20

RUN apk add --no-cache redis

COPY cleaner.sh /usr/local/bin/cleaner.sh
RUN chmod +x /usr/local/bin/cleaner.sh

CMD ["/usr/local/bin/cleaner.sh"]
