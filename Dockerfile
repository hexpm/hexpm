FROM elixir:1.3.2

RUN mix local.hex --force

RUN curl -sL https://deb.nodesource.com/setup_6.x | bash -
RUN apt-get install -y nodejs postgresql-client

RUN mkdir -p /usr/src/app
WORKDIR /usr/src/app

COPY mix.exs /usr/src/app/mix.exs
COPY mix.lock /usr/src/app/mix.lock
RUN mix deps.get

COPY package.json /usr/src/app/package.json
RUN npm install

COPY . /usr/src/app
RUN mix compile

CMD ["mix", "phoenix.server"]
