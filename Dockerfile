FROM python:3.12-alpine

# System dependencies needed by lxml, cssselect, and other optional urlwatch features
RUN apk add --no-cache \
    gcc \
    musl-dev \
    libffi-dev \
    libxml2-dev \
    libxslt-dev

# urlwatch: core monitoring engine
# apprise:  notification dispatch (used by run-check.sh)
# cssselect, lxml: CSS selector support in urlwatch filters
# jq (Python binding): JSON filter support in urlwatch filters
RUN pip install --no-cache-dir \
    urlwatch \
    apprise \
    cssselect \
    lxml \
    jq

# Non-root user for least-privilege execution
RUN adduser -D -u 1000 urlwatch

USER urlwatch
WORKDIR /app

# /config  – mounted read-only: urlwatch.yaml and urls-*.yaml files
# /cache   – mounted read-write: one cache-<tier>.db per schedule tier
# /scripts – mounted read-only: run-check.sh and any helper scripts
VOLUME ["/config", "/cache"]
