FROM python:3.12-slim

ARG CRANE_VERSION=0.20.3

RUN apt-get update -qq \
    && apt-get install -y -qq --no-install-recommends \
       ca-certificates \
       curl \
       dnsutils \
       git \
       iproute2 \
       iputils-ping \
       jq \
       less \
       net-tools \
       netcat-openbsd \
       openssh-client \
       rsync \
       sshpass \
       traceroute \
       vim \
       wget \
    && rm -rf /var/lib/apt/lists/*

RUN curl -sL "https://github.com/google/go-containerregistry/releases/download/v${CRANE_VERSION}/go-containerregistry_Linux_x86_64.tar.gz" \
    | tar -xzf - -C /usr/local/bin crane

ARG YQ_VERSION=4.45.1
RUN curl -sL "https://github.com/mikefarah/yq/releases/download/v${YQ_VERSION}/yq_linux_amd64" \
    -o /usr/local/bin/yq && chmod +x /usr/local/bin/yq

RUN pip install --no-cache-dir ansible

WORKDIR /ansible
