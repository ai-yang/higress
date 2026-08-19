ARG BASE_IMAGE
FROM ${BASE_IMAGE}

ARG FILTER_PATH
ARG SOURCE_REVISION
ARG VARIANT

COPY --chown=istio-proxy:istio-proxy ${FILTER_PATH} /var/lib/istio/envoy/golang-filter.so

LABEL org.opencontainers.image.source="https://github.com/higress-group/higress" \
      org.opencontainers.image.revision="${SOURCE_REVISION}" \
      io.higress.runtime-verification="pr4286-r2" \
      io.higress.runtime-verification.variant="${VARIANT}"
