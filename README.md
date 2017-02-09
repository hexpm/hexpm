# HexWeb

[![Build Status](https://travis-ci.org/hexpm/hex_web.svg?branch=master "Build Status")](http://travis-ci.org/hexpm/hex_web)

## Contributing

To contribute to HexWeb you need to properly set up your development environment.

Also see the client repository: [hex](https://github.com/hexpm/hex). The client uses `hex_web` for integration tests, so `hex_web` needs to support all versions the client supports. Travis tests ensures that tests are run on all supported versions.

### PostgreSQL Modules And Version

PostgreSQL version should be >= 9.4, as HexWeb uses the `jsonb` type, that is available from PostgreSQL 9.4 onward.

HexWeb requires the PostgreSQL modules [pg_trgm](http://www.postgresql.org/docs/9.4/static/pgtrgm.html) and [pgcrypto](http://www.postgresql.org/docs/9.4/static/pgcrypto.html) to be available.

This is located in the "postgresql-contrib" package, however the package name can vary depending on your operating system. If the module is not installed the ecto migrations will fail.

### Database

By default, HexWeb connects to a localhost PostgreSQL database `hexweb_dev` using the username `postgres` with the password `postgres`.

Create the database and user 'postgres' if not already done:

```sql
CREATE USER postgres;
ALTER USER postgres PASSWORD 'postgres';
CREATE DATABASE hexweb_dev;
GRANT ALL PRIVILEGES ON DATABASE hexweb_dev TO postgres;
ALTER USER postgres WITH SUPERUSER;

-- if you also want to setup the test database
CREATE DATABASE hexweb_test;
GRANT ALL PRIVILEGES ON DATABASE hexweb_test TO postgres;
ALTER DATABASE hexweb_test SET timezone TO 'UTC';
```

If you want to use another database, user or password, you can specify the
`DEV_DATABASE_URL` in the shell before doing development:

```shell
export DEV_DATABASE_URL=ecto://USER:PASSWORD@localhost/DATABASE
```

Now you are fine to run the ecto migrations:

```shell
mix ecto.migrate HexWeb.Repo
```

### Sample Data

Using the following command you can seed your local HexWeb instance with some sample data:

```shell
mix run priv/repo/seeds.exs
```

Also, all of the steps above (creating, migrating, and seeding the database) can be achieved by running:

```shell
mix ecto.setup
```

### Node Dependencies

All the Node dependencies can be installed with `npm`:

```shell
cd assets && npm install
```

These are needed for asset compilation.

### Running HexWeb

Once the database is set up you can start HexWeb:

```shell
# with console
iex -S mix phoenix.server

# without console
mix phoenix.server
```

HexWeb will be available at [http://localhost:4000/](http://localhost:4000/).

### Running Tests

By default, tests use a PostgreSQL called `hexweb_test` see above for setup.

Again, if you want to use another database, user or password, you can specify the
`TEST_DATABASE_URL` in the shell before running tests:

```shell
export TEST_DATABASE_URL='ecto://USER:PASSWORD@localhost/DATABASE'
```

Test Coverage is currently provided by ExCoveralls.

You can generate the HTML coverage report like so

```shell
MIX_ENV=test mix coveralls.html
```

Or visit the project Coveralls page at [https://coveralls.io/github/hexpm/hex_web](https://coveralls.io/github/hexpm/hex_web).

## License

    Copyright 2015 Eric Meadows-Jönsson

    Licensed under the Apache License, Version 2.0 (the "License");
    you may not use this file except in compliance with the License.
    You may obtain a copy of the License at

        http://www.apache.org/licenses/LICENSE-2.0

    Unless required by applicable law or agreed to in writing, software
    distributed under the License is distributed on an "AS IS" BASIS,
    WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
    See the License for the specific language governing permissions and
    limitations under the License.
