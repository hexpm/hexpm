# Hexpm

[![CI](https://github.com/hexpm/hexpm/workflows/CI/badge.svg)](https://github.com/hexpm/hexpm/actions?query=workflow%3ACI)

## Contributing

To contribute to Hexpm you need to properly set up your development environment.

Also see the client repository: [hex](https://github.com/hexpm/hex). The client uses `hexpm` for integration tests, so `hexpm` needs to support all versions the client supports. Travis tests ensures that tests are run on all supported versions.

### Setup

1. Run `mix setup` to install dependencies, create and seed database etc
2. Run `mix test`
3. Run `iex -S mix phx.server` and visit [http://localhost:4000/](http://localhost:4000/)

After this succeeds you should be good to go!

See [`setup` alias in mix.exs](./mix.exs) and sections below for more information or when you run into issues.

### PostgreSQL Modules And Version

PostgreSQL version should be >= 9.4, as Hexpm uses the `jsonb` type, that is available from PostgreSQL 9.4 onward.

Hexpm requires the PostgreSQL modules [pg_trgm](http://www.postgresql.org/docs/9.4/static/pgtrgm.html) and [pgcrypto](http://www.postgresql.org/docs/9.4/static/pgcrypto.html) to be available.

This is located in the "postgresql-contrib" package, however the package name can vary depending on your operating system. If the module is not installed the ecto migrations will fail.

### Database

By default, Hexpm connects to a localhost PostgreSQL database `hexpm_dev` using the username `postgres` with the password `postgres`.

Create the database and user 'postgres' if not already done:

```sh
docker-compose up -d db
```

Now you are fine to create the `hexpm_dev` database and run the ecto migrations:

```shell
mix do ecto.create, ecto.migrate
```

### Sample Data

Using the following command you can seed your local Hexpm instance with some sample data:

```shell
mix run priv/repo/seeds.exs
```

### Node Dependencies

For assets compilation we need to install Node dependencies:

```shell
cd assets && yarn install
```

If you don't have yarn installed, `cd assets && npm install` will work too.

### Running Hexpm

Once the database is set up you can start Hexpm:

```shell
# with console
iex -S mix phx.server

# without console
mix phx.server
```

Hexpm will be available at [http://localhost:4000/](http://localhost:4000/).

## License

    Copyright 2015 Six Colors AB

    Licensed under the Apache License, Version 2.0 (the "License");
    you may not use this file except in compliance with the License.
    You may obtain a copy of the License at

        http://www.apache.org/licenses/LICENSE-2.0

    Unless required by applicable law or agreed to in writing, software
    distributed under the License is distributed on an "AS IS" BASIS,
    WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
    See the License for the specific language governing permissions and
    limitations under the License.
