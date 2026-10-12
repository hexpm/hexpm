ARG ELIXIR_VERSION=1.20.4
ARG ERLANG_VERSION=29.1.1
ARG DEBIAN_VERSION=trixie-20260918-slim

FROM hexpm/elixir:${ELIXIR_VERSION}-erlang-${ERLANG_VERSION}-debian-${DEBIAN_VERSION} AS build

ENV LANG=C.UTF-8

# install build dependencies
RUN apt update && \
    apt upgrade -y && \
    apt install -y --no-install-recommends git build-essential cmake curl ca-certificates && \
    apt clean -y && rm -rf /var/lib/apt/lists/*

# install rust, the lumis CLI is built from source, and cmake for wasmtime
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
RUN mix deps.get
# The config the dependencies compile with. runtime.exs is only read by the
# release, so it's copied in right before it, and a change to it doesn't
# recompile the dependencies.
COPY config/config.exs config/prod.exs config/
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

# build release
COPY config/runtime.exs config/
COPY rel rel
RUN mix do sentry.package_source_code + release

# prepare release image
FROM debian:${DEBIAN_VERSION} AS app

RUN apt update && \
    apt upgrade -y && \
    apt install --no-install-recommends -y bash openssl ca-certificates git && \
    apt clean -y && rm -rf /var/lib/apt/lists/*

# The release creates /app/tmp when it starts and writes its runtime config
# there, so /app is nobody's.
RUN mkdir /app && chown nobody:nogroup /app
WORKDIR /app

# A --link copy doesn't depend on the layers before it, so a build that has
# them in its cache doesn't have to download them. --link can't look up user
# names, so the owner is nobody:nogroup by ID.
COPY --link --from=build --chown=65534:65534 /app/_build/prod/rel/hexpm ./
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
