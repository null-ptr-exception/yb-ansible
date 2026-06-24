FROM alpine:3.22 AS downloader

ARG YB_VERSION=2025.2.3.2
ARG YB_BUILD=b1
ARG YB_ARCH=linux-x86_64
ARG YB_SHA256=ea23027f6cc46f0b87123e712f6a0cdbb9676c84d6bc8f4f0124b104de556f97

RUN wget -O /yugabyte.tar.gz \
      "https://software.yugabyte.com/releases/${YB_VERSION}/yugabyte-${YB_VERSION}-${YB_BUILD}-${YB_ARCH}.tar.gz" \
    && echo "${YB_SHA256}  /yugabyte.tar.gz" | sha256sum -c -

FROM scratch

COPY --from=downloader /yugabyte.tar.gz /tarball/yugabyte.tar.gz
