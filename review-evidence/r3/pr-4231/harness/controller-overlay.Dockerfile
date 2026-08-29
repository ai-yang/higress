ARG BASE_IMAGE
FROM ${BASE_IMAGE}

ARG SOURCE_SHA
ARG BINARY_SHA256
LABEL org.opencontainers.image.revision="${SOURCE_SHA}"
LABEL io.higress.pr4231.binary.sha256="${BINARY_SHA256}"

COPY --chown=1337:1337 higress /usr/local/bin/higress

USER 1337:1337
ENTRYPOINT ["/usr/local/bin/higress"]
