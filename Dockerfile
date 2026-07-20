ARG ELIXIR_VERSION=1.19.5
ARG ERLANG_VERSION=28.5
ARG DEBIAN_VERSION=trixie-20260505-slim

FROM hexpm/elixir:${ELIXIR_VERSION}-erlang-${ERLANG_VERSION}-debian-${DEBIAN_VERSION} AS build

ENV LANG=C.UTF-8

# install build dependencies
RUN apt update && \
    apt upgrade -y && \
    apt install -y --no-install-recommends git build-essential curl ca-certificates && \
    apt clean -y && rm -rf /var/lib/apt/lists/*

# install rust, the lumis NIF is built from source
RUN curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --profile minimal --default-toolchain stable
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
COPY config config
RUN mix deps.get
RUN mix deps.compile

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
