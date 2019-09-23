FROM erlang:22.0-alpine AS build

# FROM https://github.com/c0b/docker-elixir/blob/master/1.9/alpine/Dockerfile
# elixir expects utf8.
ENV ELIXIR_VERSION="v1.9.1" \
LANG=C.UTF-8

RUN set -xe \
&& ELIXIR_DOWNLOAD_URL="https://github.com/elixir-lang/elixir/archive/${ELIXIR_VERSION}.tar.gz" \
&& ELIXIR_DOWNLOAD_SHA256="94daa716abbd4493405fb2032514195077ac7bc73dc2999922f13c7d8ea58777" \
&& buildDeps=' \
  ca-certificates \
  curl \
  make \
' \
&& apk add --no-cache --virtual .build-deps $buildDeps \
&& curl -fSL -o elixir-src.tar.gz $ELIXIR_DOWNLOAD_URL \
&& echo "$ELIXIR_DOWNLOAD_SHA256  elixir-src.tar.gz" | sha256sum -c - \
&& mkdir -p /usr/local/src/elixir \
&& tar -xzC /usr/local/src/elixir --strip-components=1 -f elixir-src.tar.gz \
&& rm elixir-src.tar.gz \
&& cd /usr/local/src/elixir \
&& make install clean \
&& apk del .build-deps

# install build dependencies
RUN apk add --update git build-base nodejs yarn python

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

# build assets
COPY assets assets
RUN cd assets && yarn install && yarn run webpack --mode production
RUN mix phx.digest

# build project
COPY priv priv
COPY lib lib
RUN mix compile

# build release
COPY rel rel
RUN mix release

# prepare release image
FROM alpine:3.9 AS app
RUN apk add --update bash openssl

RUN mkdir /app
WORKDIR /app

COPY --from=build /app/_build/prod/rel/hexpm ./
RUN chown -R nobody: /app
USER nobody

ENV HOME=/app
