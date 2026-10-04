ARG ELIXIR_VERSION=1.20.4
ARG ERLANG_VERSION=29.1.1
ARG DEBIAN_VERSION=trixie-20260918-slim

FROM hexpm/elixir:${ELIXIR_VERSION}-erlang-${ERLANG_VERSION}-debian-${DEBIAN_VERSION} AS build

ENV LANG=C.UTF-8

# install build dependencies
RUN apt update && \
    apt upgrade -y && \
    apt install -y --no-install-recommends git build-essential cmake curl ca-certificates util-linux-extra && \
    apt clean -y && rm -rf /var/lib/apt/lists/*

# install rust, the lumis NIF and CLI and the mdex_native NIF are built from source
ARG RUST_VERSION=1.99.0
ARG RUSTUP_VERSION=1.29.1
RUN arch="$(uname -m)" && \
    case "$arch" in \
      aarch64) sha256=15f6e4ce9f583b929c996c91562bad6d4454f3281de858b02cdfdef615fac433 ;; \
      x86_64) sha256=dda7234360b7f578ca8b0ddcb80145646fa61a67c1720a5abc7051b35c9fcb71 ;; \
      *) echo "unsupported architecture: $arch" && exit 1 ;; \
    esac && \
    curl --proto '=https' --tlsv1.2 -sSfo /tmp/rustup-init \
      "https://static.rust-lang.org/rustup/archive/${RUSTUP_VERSION}/${arch}-unknown-linux-gnu/rustup-init" && \
    echo "${sha256}  /tmp/rustup-init" | sha256sum -c - && \
    chmod +x /tmp/rustup-init && \
    /tmp/rustup-init -y --no-modify-path --profile minimal --default-toolchain "${RUST_VERSION}" && \
    rm /tmp/rustup-init
ENV PATH="/root/.cargo/bin:${PATH}"

# tree-sitter grammars generated with CLI < 0.26.4 ship an array.h whose
# macros violate strict aliasing, which gcc -O2 miscompiles into heap
# corruption (tree-sitter/tree-sitter-haskell#144)
ENV CFLAGS="-fno-strict-aliasing"

# mdex_native links its own copy of the grammars, and its precompiled NIF is
# built without the flag above
ENV MDEX_NATIVE_BUILD=1

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

# Bundle the IP geolocation database into the release (priv/geoip/country.mmdb).
# The build fails if the download fails — no silent fallback to a missing file.
# If the current month's file isn't published yet (DB-IP releases in the first
# few days), the task automatically retries with the previous month.
# Pass --build-arg GEOIP_MONTH=YYYY-MM to pin a specific release and bust the
# Docker layer cache.
ARG GEOIP_MONTH
RUN mix download_geoip${GEOIP_MONTH:+ --month ${GEOIP_MONTH}}

# Parsers for syntax highlighting (priv/lumis), and the seccomp filter for the
# processes that run it (priv/lumis_sandbox), written here because a filter is
# for one CPU architecture. Pass --build-arg LUMIS_LANGUAGES="elixir erlang" to
# replace the configured list.
ARG LUMIS_LANGUAGES
RUN mix hexpm.lumis_cache ${LUMIS_LANGUAGES}
RUN mix hexpm.lumis_seccomp

# build release
COPY rel rel
RUN mix do sentry.package_source_code + release

# prepare release image
FROM debian:${DEBIAN_VERSION} AS app

RUN apt update && \
    apt upgrade -y && \
    apt install --no-install-recommends -y bash openssl ca-certificates git && \
    apt clean -y && rm -rf /var/lib/apt/lists/*

RUN mkdir /app
WORKDIR /app

COPY --from=build /app/_build/prod/rel/hexpm ./
# The release stays owned by root, so the processes that highlight package
# source, which run as nobody too, cannot change it. nobody writes to tmp,
# RELEASE_TMP and :tmp_dir, and to priv/lumis, where parsers are downloaded.
RUN mkdir tmp && chown -R nobody: tmp lib/hexpm-*/priv/lumis
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
