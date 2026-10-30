# Hexpm

[![CI](https://github.com/hexpm/hexpm/workflows/CI/badge.svg)](https://github.com/hexpm/hexpm/actions?query=workflow%3ACI)

API server and website for <https://hex.pm>.

## Contributing

To contribute to Hexpm you need to properly set up your development environment.

Also see the client repository: [hex](https://github.com/hexpm/hex). The client uses `hexpm` for integration tests, so `hexpm` needs to support all versions the client supports. CI ensures that tests are run on all supported versions.

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

Development object storage is shared across worktrees under the operating system's temporary directory. Set `HEXPM_LOCAL_STORE_DIR` to use a different shared location.

Create the database and user 'postgres' if not already done:

```sh
docker-compose up -d db
```

Now you are fine to create the `hexpm_dev` database and run the ecto migrations:

```shell
mix do ecto.create + ecto.migrate
```

### Sample Data

Using the following command you can seed your local Hexpm instance with some sample data:

```shell
mix run priv/repo/seeds.exs
```

### Node Dependencies

It's recommended to enable [Corepack](https://yarnpkg.com/corepack) for a better developer experience:

```shell
corepack enable
```

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

### IP Geolocation (Audit Log Locations)

The dashboard audit log (`/dashboard/audit-logs`) shows the country of each
entry's IP, resolved at render time via the `:geo_impl` implementation:

- **dev / test** use `Hexpm.Geo.Local` — no database required. It resolves IPs
  from the `:geo_local_lookups` map in `config/dev.exs` (localhost is mapped by
  default); add entries there to exercise other countries.
- **production** uses `Hexpm.Geo.Geolix`, which reads an MMDB IP-to-country
  database via [`geolix`](https://hex.pm/packages/geolix).

The production database is the free
[DB-IP IP-to-Country Lite](https://db-ip.com/db/download/ip-to-country-lite) file
(CC BY 4.0 — attribution is rendered on the page; any MaxMind-compatible MMDB
also works).

**Docker (default): nothing to do.** The image fetches the database at build
time and bakes it into the release, and the app finds it automatically —
geolocation works out of the box. Each image build re-fetches the current file
(DB-IP refreshes monthly), so routine rebuilds keep it reasonably fresh.

**Other deployments / custom location:** download it and point Hexpm at the file:

```shell
mix download_geoip                            # -> priv/geoip/country.mmdb
export HEXPM_GEOIP_COUNTRY_PATH=priv/geoip/country.mmdb
```

Re-run the task and restart (or call `Geolix.reload_databases/0`) to update.

> **Fail-soft:** if no database is found the app boots normally and audit log
> locations are simply omitted until one is provisioned. `HEXPM_GEOIP_COUNTRY_PATH`
> overrides the baked-in default.

### Billing Integration Tests

Integration tests exercise the full chain: hexpm -> hexpm_billing -> Stripe. They are excluded from regular `mix test` runs and require additional setup.

#### Stripe Sandbox Setup

1. **Create a Stripe sandbox** (if you don't already have one):

   Go to the [Stripe Dashboard](https://dashboard.stripe.com), open the account picker, click "Switch to sandbox", then "Create sandbox". Give it a name (e.g. "hexpm-dev").

2. **Install and authenticate the Stripe CLI:**

   ```shell
   brew install stripe/stripe-cli/stripe
   stripe login
   ```

   This opens a browser where you select which sandbox to log into. The CLI generates restricted keys valid for 90 days, stored in `~/.config/stripe/config.toml`.

3. **Configure hexpm_billing with your sandbox keys:**

   Copy the API keys from your sandbox's [API keys page](https://dashboard.stripe.com/test/apikeys) and update `hexpm_billing/config/dev.exs`:

   - `stripe_secret_key` — your sandbox secret key (`sk_test_...`)
   - `stripe_publishable_key` — your sandbox publishable key (`pk_test_...`)

4. **Forward Stripe webhooks to hexpm_billing:**

   ```shell
   stripe listen --forward-to localhost:4001/webhooks/payments
   ```

   The CLI will print a webhook signing secret (`whsec_...`). Update `stripe_signing_secret_key` in `hexpm_billing/config/dev.exs` with this value. The secret stays the same between CLI restarts.

#### Prerequisites

1. **hexpm_billing running locally on port 4001:**

   ```shell
   # In the hexpm_billing repo
   mix deps.get
   mix ecto.setup
   MIX_ENV=dev mix phx.server
   ```

2. **ChromeDriver installed** (for browser tests):

   ```shell
   brew install chromedriver
   ```

3. **Stripe CLI forwarding webhooks** (see above):

   ```shell
   stripe listen --forward-to localhost:4001/webhooks/payments
   ```

#### Running

```shell
# All integration tests
mix test --only integration

# Only browser/SCA tests
mix test test/hexpm_web/integration/sca_test.exs --include integration
```

## Staged publishing

`HEXPM_STAGED_PUBLISHING_MODE` defaults to `off`. Set it to `beta` with comma-separated
`HEXPM_STAGED_PUBLISHING_BETA_USERS` and `HEXPM_STAGED_PUBLISHING_BETA_ORGANIZATIONS`,
or to `enabled`. Public packages follow their owners in beta; private packages
follow their organization.

Staged package and documentation tarballs use the existing repo bucket under
`staged/`, with private, non-cacheable responses. The CDN origin identity must be
denied access to this prefix, and backups must exclude it. Staged releases can be
approved for seven days; approval, rejection, restaging and expiry enqueue artifact
cleanup.
S3 lifecycle rules expire remaining current objects after 14 days and noncurrent
versions after one day. Lifecycle deletion is asynchronous. Deploy the
hexpm-ops storage rules and backup exclusion before enabling staged publishing.
Development and test use the existing local and memory repo stores.

Each package has an optional approval setting covering all API keys and workload
identities that publish it, on by default for new packages. Existing packages keep
direct publishing until approval is enabled. Full owners configure it under
Settings > Publish approval; changes require two-factor authentication and fresh
sudo, and disabling sends a notification to full owners and owning organization
administrators.
The rollout flag controls when these settings take effect; it doesn't gate
Workload Identity availability. Both public and private publishing follow the
package's setting.
An organization administrator can require approval for API keys and workload
identities in its private repository under Publish approval in the dashboard.
User OAuth publishes with an OTP remain direct.

Publish approval doesn't change how API keys and workload identities are created
or managed. A key is only created by a signed-in person: on the dashboard behind
sudo, which asks for the 2FA code when the account has 2FA, or through the API with
an OAuth token and a valid `X-Hex-OTP`. API keys can't create keys.

Publish approval doesn't change who can add owners or organization members. An API
key with the `owners` or `members` permission can add an owner or member whose own
account publishes with OAuth and an OTP, which isn't staged. The user and
organization API key pages list the packages requiring approval.

Review and approval are available under
Staged releases. Approval and rejection require 2FA and forced sudo; approval also
binds to the displayed package and documentation checksums. Staged releases expire
after seven days, and a periodic worker removes them and queues artifact deletion.

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
