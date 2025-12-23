# Bezgelor Umbrella App Dockerfile
#
# Builds and runs all servers: Portal (HTTP), Auth (6600), Realm (23115), World (24000)
#
# https://hub.docker.com/r/hexpm/elixir/tags?name=ubuntu
# https://hub.docker.com/_/debian/tags

ARG ELIXIR_VERSION=1.19.4
ARG OTP_VERSION=28.2
ARG DEBIAN_VERSION=trixie-20251208-slim

ARG BUILDER_IMAGE="docker.io/hexpm/elixir:${ELIXIR_VERSION}-erlang-${OTP_VERSION}-debian-${DEBIAN_VERSION}"
ARG RUNNER_IMAGE="docker.io/debian:${DEBIAN_VERSION}"

FROM ${BUILDER_IMAGE} AS builder

# Install build dependencies including Node.js for assets
RUN apt-get update \
  && apt-get install -y --no-install-recommends build-essential git curl \
  && curl -fsSL https://deb.nodesource.com/setup_20.x | bash - \
  && apt-get install -y --no-install-recommends nodejs \
  && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Install hex + rebar
RUN mix local.hex --force \
  && mix local.rebar --force

# Set build ENV
ENV MIX_ENV="prod"

# Copy umbrella mix files
COPY mix.exs mix.lock ./
COPY apps/bezgelor_core/mix.exs apps/bezgelor_core/
COPY apps/bezgelor_crypto/mix.exs apps/bezgelor_crypto/
COPY apps/bezgelor_db/mix.exs apps/bezgelor_db/
COPY apps/bezgelor_data/mix.exs apps/bezgelor_data/
COPY apps/bezgelor_protocol/mix.exs apps/bezgelor_protocol/
COPY apps/bezgelor_auth/mix.exs apps/bezgelor_auth/
COPY apps/bezgelor_realm/mix.exs apps/bezgelor_realm/
COPY apps/bezgelor_world/mix.exs apps/bezgelor_world/
COPY apps/bezgelor_api/mix.exs apps/bezgelor_api/
COPY apps/bezgelor_portal/mix.exs apps/bezgelor_portal/

# Get dependencies
RUN mix deps.get --only $MIX_ENV

# Copy config files
COPY config config

# Compile dependencies
RUN mix deps.compile

# Setup assets (esbuild, tailwind binaries)
RUN mix assets.setup

# Copy all application source
COPY apps apps

# Install npm dependencies for frontend assets
RUN cd apps/bezgelor_portal/assets && npm install

# Copy static data files
COPY apps/bezgelor_data/priv apps/bezgelor_data/priv

# Compile the release
RUN mix compile

# Build assets
RUN mix assets.deploy

# Copy release configuration
COPY apps/bezgelor_portal/rel apps/bezgelor_portal/rel

# Build the release
RUN mix release

# Start runtime image
FROM ${RUNNER_IMAGE} AS final

RUN apt-get update \
  && apt-get install -y --no-install-recommends libstdc++6 openssl libncurses6 locales ca-certificates \
  && rm -rf /var/lib/apt/lists/*

# Set the locale
RUN sed -i '/en_US.UTF-8/s/^# //g' /etc/locale.gen \
  && locale-gen

ENV LANG=en_US.UTF-8
ENV LANGUAGE=en_US:en
ENV LC_ALL=en_US.UTF-8

WORKDIR "/app"
RUN chown nobody /app

ENV MIX_ENV="prod"

# Copy the release
COPY --from=builder --chown=nobody:root /app/_build/${MIX_ENV}/rel/bezgelor_portal ./

USER nobody

# Expose all server ports
# Portal (HTTP)
EXPOSE 4000
# Auth (STS)
EXPOSE 6600
# Realm
EXPOSE 23115
# World
EXPOSE 24000

CMD ["/app/bin/server"]
