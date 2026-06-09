FROM python:3.12-slim

ARG CRANE_VERSION=0.21.5
ARG DOCKER_VERSION=26.1.1
ARG DOCKER_SHA256=c0ef0ee7d00deb803a6f5fa78d83ec8cbe1848eaaea9fb7071364d526624278f

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

# Install Docker CLI
RUN curl -fsSL -o /tmp/docker.tgz \
      "https://download.docker.com/linux/static/stable/x86_64/docker-${DOCKER_VERSION}.tgz" \
    && echo "${DOCKER_SHA256}  /tmp/docker.tgz" | sha256sum -c - \
    && tar -xzf /tmp/docker.tgz -C /tmp \
    && mv /tmp/docker/docker /usr/local/bin/docker \
    && rm -rf /tmp/docker /tmp/docker.tgz

RUN curl -fsSL -o /tmp/crane.tar.gz \
      "https://github.com/google/go-containerregistry/releases/download/v${CRANE_VERSION}/go-containerregistry_Linux_x86_64.tar.gz" \
    && echo "9f823ae5ee25803161110f957b5fd4538f714d40cdf25dacb4914fefafd246bf  /tmp/crane.tar.gz" | sha256sum -c - \
    && tar -xzf /tmp/crane.tar.gz -C /usr/local/bin crane \
    && rm /tmp/crane.tar.gz

ARG YQ_VERSION=4.53.2
RUN curl -fsSL "https://github.com/mikefarah/yq/releases/download/v${YQ_VERSION}/yq_linux_amd64" \
      -o /tmp/yq \
    && echo "d56bf5c6819e8e696340c312bd70f849dc1678a7cda9c2ad63eebd906371d56b  /tmp/yq" | sha256sum -c - \
    && install -m 0755 /tmp/yq /usr/local/bin/yq \
    && rm /tmp/yq

RUN pip install --no-cache-dir 'ansible-core>=2.16,<2.17' docker \
    && ansible-galaxy collection install community.docker

WORKDIR /ansible
COPY . .
