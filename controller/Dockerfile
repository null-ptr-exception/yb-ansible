FROM python:3.12-slim

ARG CRANE_VERSION=0.21.5

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

RUN curl -fsSL -o /tmp/crane.tar.gz \
      "https://github.com/google/go-containerregistry/releases/download/v${CRANE_VERSION}/go-containerregistry_Linux_x86_64.tar.gz" \
    && echo "9f823ae5ee25803161110f957b5fd4538f714d40cdf25dacb4914fefafd246bf  /tmp/crane.tar.gz" | sha256sum -c - \
    && tar -xzf /tmp/crane.tar.gz -C /usr/local/bin crane \
    && rm /tmp/crane.tar.gz

ARG YQ_VERSION=4.53.2
RUN curl -sL "https://github.com/mikefarah/yq/releases/download/v${YQ_VERSION}/yq_linux_amd64" \
    -o /usr/local/bin/yq && chmod +x /usr/local/bin/yq

RUN pip install --no-cache-dir 'ansible-core>=2.16,<2.17'

WORKDIR /ansible
COPY . .
