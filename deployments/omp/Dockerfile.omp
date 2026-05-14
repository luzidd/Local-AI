FROM docker.io/oven/bun:debian

# Install system dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    curl \
    git \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# Install oh-my-pi globally
RUN bun install -g @oh-my-pi/pi-coding-agent

# Create workspace directory
RUN mkdir -p /workspace

WORKDIR /workspace

ENTRYPOINT ["omp"]
