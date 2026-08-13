ARG ELIXIR_VERSION=1.19.5
ARG ERLANG_VERSION=28.5.0.4
ARG DEBIAN_VERSION=trixie-20260713-slim

FROM hexpm/elixir:${ELIXIR_VERSION}-erlang-${ERLANG_VERSION}-debian-${DEBIAN_VERSION} AS build

ENV LANG=C.UTF-8

# install build dependencies
RUN apt update && \
    apt upgrade -y && \
    apt install -y --no-install-recommends git build-essential && \
    apt clean -y && rm -rf /var/lib/apt/lists/*

# prepare build dir
RUN mkdir /app
WORKDIR /app

# install hex + rebar
RUN mix local.hex --force && \
    mix local.rebar --force

# set build ENV
ENV MIX_ENV=prod

# install mix dependencies
COPY mix.exs mix.lock ./
COPY config config
RUN mix deps.get
# Compiling dependencies across multiple OS processes
# https://mix.hexdocs.pm/Mix.Tasks.Deps.Compile.html#module-compiling-dependencies-across-multiple-os-processes
RUN <<EOF
  CORES=$(nproc 2>/dev/null || echo 2)
  PARTITIONS=$(( CORES / 2 ))
  [ "$PARTITIONS" -lt 1 ] && PARTITIONS=1
  [ "$PARTITIONS" -gt 4 ] && PARTITIONS=4
  MIX_OS_DEPS_COMPILE_PARTITION_COUNT=$PARTITIONS mix deps.compile
EOF

# build project and assets
COPY priv priv
COPY assets assets
COPY lib lib
RUN mix assets.deploy
RUN mix compile

# build release
COPY rel rel
RUN mix do sentry.package_source_code, release

# prepare release image
FROM debian:${DEBIAN_VERSION} AS app

RUN apt update && \
    apt upgrade -y && \
    apt install --no-install-recommends -y bash openssl ca-certificates git && \
    apt clean -y && rm -rf /var/lib/apt/lists/*

RUN mkdir /app
WORKDIR /app

COPY --from=build /app/_build/prod/rel/hexpm ./
RUN chown -R nobody: /app
USER nobody

ENV HOME=/app
ENV LANG=C.UTF-8

# Declared here, in the last stage, so a new commit does not invalidate the
# build cache for everything above it. PromEx reads these to report which
# revision is running.
# Defaulted, because PromEx treats an empty variable as present and would
# label the metric with a blank rather than saying it is unknown.
ARG GIT_SHA=unknown
ARG GIT_AUTHOR=unknown
ENV GIT_SHA=${GIT_SHA}
ENV GIT_AUTHOR=${GIT_AUTHOR}
