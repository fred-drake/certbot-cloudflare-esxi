FROM python:3.9.10 as base
ENV HADOLINT_VERSION=2.10.0
WORKDIR /tmp
SHELL ["/bin/bash", "-o", "pipefail", "-c"]
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        python3-pip openssh-client \
    && rm -rf /var/cache/apt/archives
RUN pip install --no-cache-dir certbot certbot-dns-cloudflare

FROM base as devbuilder
WORKDIR /tmp/builder
RUN dpkg --print-architecture > arch
RUN if [ "$(cat arch)" = "amd64" ]; then echo x86_64 > arch; fi
RUN curl -LO "https://github.com/hadolint/hadolint/releases/download/v${HADOLINT_VERSION}/hadolint-Linux-$(cat arch)" && \
    chmod +x "hadolint-Linux-$(cat arch)" && \
    mv "hadolint-Linux-$(cat arch)" /usr/local/bin/hadolint

FROM base as development
COPY --from=devbuilder /usr/local/bin/hadolint /usr/local/bin/hadolint
WORKDIR /workspaces/certbot-cloudflare-esxi-docker

FROM base
