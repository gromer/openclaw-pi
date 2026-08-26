FROM debian:bookworm-slim
ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update && apt-get install -y --no-install-recommends bash ca-certificates git jq python3 ripgrep \
    && rm -rf /var/lib/apt/lists/* && useradd --uid 1000 --create-home --shell /bin/bash sandbox
USER 1000:1000
WORKDIR /workspace
CMD ["sleep", "infinity"]

