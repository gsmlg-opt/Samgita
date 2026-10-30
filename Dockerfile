# Multi-stage Dockerfile for Samgita production deployment
# Based on official Elixir Docker best practices

ARG ELIXIR_VERSION=1.19.7
ARG OTP_VERSION=28.5.0.8
ARG DEBIAN_VERSION=bookworm-20261027-slim

ARG BUILDER_IMAGE="hexpm/elixir:${ELIXIR_VERSION}-erlang-${OTP_VERSION}-debian-${DEBIAN_VERSION}"
ARG RUNNER_IMAGE="debian:${DEBIAN_VERSION}"

################################################################################
# Stage 1: Build Environment
################################################################################
FROM ${BUILDER_IMAGE} AS builder

ARG BUN_VERSION=1.3.13

# Install build dependencies
RUN apt-get update -y && apt-get install -y \
    build-essential \
    git \
    curl \
    ca-certificates \
    postgresql-client \
    unzip \
    && rm -rf /var/lib/apt/lists/*

# Match the verified frozen asset toolchain used in CI.
RUN curl -fsSL https://bun.sh/install | bash -s "bun-v${BUN_VERSION}"
ENV PATH="/root/.bun/bin:${PATH}"

# Prepare build directory
WORKDIR /app

# Install hex + rebar
RUN mix local.hex --force && \
    mix local.rebar --force

# Set build ENV
ENV MIX_ENV="prod"

# Install mix dependencies
COPY mix.exs mix.lock ./
COPY config config
COPY apps/samgita/mix.exs apps/samgita/mix.exs
COPY apps/samgita_web/mix.exs apps/samgita_web/mix.exs
COPY apps/samgita_protocol/mix.exs apps/samgita_protocol/mix.exs
COPY apps/samgita_protocol_websocket/mix.exs apps/samgita_protocol_websocket/mix.exs
COPY apps/samgita_protocol_codex/mix.exs apps/samgita_protocol_codex/mix.exs
COPY apps/samgita_codex_driver/mix.exs apps/samgita_codex_driver/mix.exs
COPY apps/samgita_protocol_codex/config apps/samgita_protocol_codex/config
COPY apps/samgita_codex_driver/config apps/samgita_codex_driver/config

RUN mix deps.get --only $MIX_ENV

# Local path dependencies need their complete sources before compilation.
COPY apps/samgita_protocol apps/samgita_protocol
COPY apps/samgita_protocol_websocket apps/samgita_protocol_websocket
COPY apps/samgita_protocol_codex apps/samgita_protocol_codex
COPY apps/samgita_codex_driver apps/samgita_codex_driver
COPY apps/samgita apps/samgita
COPY apps/samgita_web apps/samgita_web

RUN mix deps.compile

# Install JavaScript dependencies
WORKDIR /app/apps/samgita_web
RUN bun install --frozen-lockfile

# Build assets
WORKDIR /app
ENV MIX_BUN_PATH="/root/.bun/bin/bun"
RUN mix assets.deploy

# Compile the release
RUN mix compile

# Changes to config/runtime.exs don't require recompiling the code
COPY config/runtime.exs config/

# Build the release
RUN mix release

################################################################################
# Stage 2: Runtime Environment
################################################################################
FROM ${RUNNER_IMAGE}

# Install runtime dependencies
RUN apt-get update -y && \
    apt-get install -y \
    libstdc++6 \
    openssl \
    libncurses5 \
    locales \
    ca-certificates \
    postgresql-client \
    curl \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

# Set locale
RUN sed -i '/en_US.UTF-8/s/^# //g' /etc/locale.gen && locale-gen
ENV LANG en_US.UTF-8
ENV LANGUAGE en_US:en
ENV LC_ALL en_US.UTF-8

# Create app user
RUN useradd --create-home --shell /bin/bash app
WORKDIR /home/app

# Set runner ENV
ENV MIX_ENV="prod"
ENV HOME=/home/app

# Copy built release from builder
COPY --from=builder --chown=app:app /app/_build/prod/rel/samgita ./

USER app

# Expose HTTP port
EXPOSE 3110

# Set up entrypoint
COPY --chown=app:app deployment/docker/entrypoint.sh ./entrypoint.sh
RUN chmod +x ./entrypoint.sh

ENTRYPOINT ["./entrypoint.sh"]

# Start command
CMD ["bin/samgita", "start"]
