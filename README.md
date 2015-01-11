# HexWeb

[![Build Status](https://travis-ci.org/hexpm/hex_web.svg?branch=master "Build Status")](http://travis-ci.org/hexpm/hex_web)

## Contributing

To contribute to HexWeb you need to properly set up your development environment.

Also see the client repository: [hex](https://github.com/hexpm/hex). The client uses `hex_web` for integration tests, so `hex_web` needs to support all versions the client supports. Travis tests ensures that tests are run on all supported versions.

### PostgreSQL Modules

HexWeb requires the PostgreSQL modules [pg_trgm](http://www.postgresql.org/docs/9.3/static/pgtrgm.html) and [pgcrypto](http://www.postgresql.org/docs/9.3/static/pgcrypto.html) to be available.

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
mix run scripts/sample_data.exs
```

### Running HexWeb

Once the database is set up you can start HexWeb:

```shell
# with console
iex -S mix run

# without console
mix run --no-halt
```

HexWeb will be available at [http://localhost:4000/](http://localhost:4000/).

### Running Tests

By default, tests use a PostgreSQL called `hexweb_test` see above for setup.

Again, if you want to use another database, user or password, you can specify the
`TEST_DATABASE_URL` in the shell before running tests:

```shell
export TEST_DATABASE_URL='ecto://USER:PASSWORD@localhost/DATABASE'
```
