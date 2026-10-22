# Multi-stage Dockerfile for Samgita production deployment
# Based on official Elixir Docker best practices

ARG ELIXIR_VERSION=1.18.5
ARG OTP_VERSION=27.3.4.17
ARG DEBIAN_VERSION=bookworm-20260824-slim

ARG BUILDER_IMAGE="hexpm/elixir:${ELIXIR_VERSION}-erlang-${OTP_VERSION}-debian-${DEBIAN_VERSION}"
ARG RUNNER_IMAGE="debian:${DEBIAN_VERSION}"

################################################################################
# Stage 1: Build Environment
################################################################################
FROM ${BUILDER_IMAGE} AS builder

# Install build dependencies
RUN apt-get update -y && apt-get install -y \
    build-essential \
    git \
    curl \
    ca-certificates \
    postgresql-client \
    unzip \
    && rm -rf /var/lib/apt/lists/*

# Install Bun for asset building
RUN curl -fsSL https://bun.sh/install | bash
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

RUN mix deps.get --only $MIX_ENV
RUN mix deps.compile

# Copy application code
COPY apps/samgita apps/samgita
COPY apps/samgita_web apps/samgita_web

# Install JavaScript dependencies
WORKDIR /app/apps/samgita_web
RUN bun install --frozen-lockfile

# Build assets
WORKDIR /app
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
