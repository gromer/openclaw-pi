# Multi-architecture index digest; refresh deliberately with `docker buildx imagetools inspect`.
FROM debian:bookworm-slim@sha256:88200866dfff7ea7f5cbcb6ec7c8a701889efe6fe859fe64d6990e4b07ea4171
ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update && apt-get install -y --no-install-recommends bash ca-certificates git jq python3 ripgrep \
    && rm -rf /var/lib/apt/lists/* && useradd --uid 1000 --create-home --shell /bin/bash sandbox
USER 1000:1000
WORKDIR /workspace
CMD ["sleep", "infinity"]
