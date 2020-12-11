## Self-hosting

In this guide we'll learn how to serve Hex packages using your own server. First, though, some background on what a Hex server really is.

### Hex specifications

A Hex server must follow [Hex specifications](https://github.com/hexpm/specifications). An example server, and a reference implementation, is <https://github.com/hexpm/hexpm> that powers <https://hex.pm>. The Hex team also maintains a lower-level library, <https://github.com/hexpm/hex_core>, that you can use to build and interact with Hex servers.

A Hex server consists of two [endpoints](https://github.com/hexpm/specifications/blob/master/endpoints.md):

1. HTTP API - used for publishing packages, packages search, and administrative tasks.
2. Repository - read-only endpoint that delivers registry resources and package tarballs.

To run a basic Hex server you only need to implement the Repository endpoint.

### Building the registry

Hex v0.21 introduced a [`mix hex.registry build`](https://hexdocs.pm/hex/Mix.Tasks.Hex.Registry.html) task which provides an easy way to build a local registry.

`mix hex.registry build` needs three things:

- the name of the registry
- a directory to hold public files
- a private key used to sign the registry.

Let's create an "acme" registry, generate a random private key, a `public` directory, and finally let's build the registry:

```
$ mkdir acme
$ cd acme
$ openssl genrsa -out private_key.pem
$ mkdir public
$ mix hex.registry build public --name=acme --private-key=private_key.pem
* creating public/public_key
* creating public/tarballs
* creating public/names
* creating public/versions
```

and that's it! Now, all we need to do is start a HTTP server that exposes the `public` directory and we can point Hex clients to it. However, let's add a package to our repository first.

To publish a package you need to copy the tarball to `public/tarballs` and re-build the registry. You can build your own package (using [`mix hex.build`](https://hexdocs.pm/hex/Mix.Tasks.Hex.Build.html)) or simply use an existing one. Let's do the latter:

```
$ mix hex.package fetch decimal 2.0.0
decimal v2.0.0 downloaded to decimal-2.0.0.tar
$ cp decimal-2.0.0.tar public/tarballs/
$ mix hex.registry build public --name=acme --private-key=private_key.pem
* creating public/packages/decimal
* updating public/names
* updating public/versions
```

Now let's test our repository. We can use the built-in server that ships with Erlang/OTP to serve the `public` directory:

```
$ erl -s inets -eval 'inets:start(httpd,[{port,8000},{server_name,"localhost"},{server_root,"."},{document_root,"public"}]).'
```

And let's now add the repository and try fetching the package that we just published:

```
$ mix hex.repo add acme http://localhost:8000 --public-key=public/public_key
$ mix hex.package fetch decimal 2.0.0 --repo=acme
decimal v2.0.0 downloaded to decimal-2.0.0.tar
```

If everything went well you should see that the package was downloaded from your local server!

In the next sections we'll cover how we can deploy our registry to production.

### Deploying to S3

Deploying to Amazon S3 (or similar cloud services) is probably the easiest way to have a reliable Hex repository.

If you already have an S3 bucket, use e.g. [AWS CLI](https://aws.amazon.com/cli/) to sync the contents of the `public/` directory
like this:

```
$ aws s3 sync public s3://my-bucket
```

Your repository should now be available under an URL like: `https://<bucket>.s3.<region>.amazonaws.com` or however you configured your bucket.

If you don't yet have a bucket, create one! By default, files stored on S3 are not publicly accessible. You can enable public access by setting the following bucket policy in your bucket's properties:

```json
{
  "Version": "2008-10-17",
  "Statement": [
    {
      "Sid": "AllowPublicRead",
      "Effect": "Allow",
      "Principal": {
        "AWS": "*"
      },
      "Action": "s3:GetObject",
      "Resource": "arn:aws:s3:::my-bucket/*"
    }
  ]
}
```

You may also consider adding an IAM policy for the user accessing the bucket:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "VisualEditor0",
      "Effect": "Allow",
      "Action": [
        "s3:PutObject",
        "s3:GetObject",
        "s3:ListBucket",
        "s3:DeleteObject"
      ],
      "Resource": [
        "arn:aws:s3:::my-bucket",
        "arn:aws:s3:::my-bucket/*"
      ]
    }
  ]
}
```

See [Amazon S3 docs](https://docs.aws.amazon.com/s3/index.html) for more information.

### Deploying with Plug.Cowboy & Docker

If you need any customizations to your Hex server, you may consider creating a proper Elixir project. Let's create one: we'll serve static files, add basic authentication, configure it via environment variables and prepare for deployment with Docker.

Let's start a new project:

```
$ mix new my_app --sup
$ cd my_app
```

And add dependencies:

```elixir
# mix.exs

defp deps do
  [
    {:plug, "~> 1.11"},
    {:plug_cowboy, "~> 2.4"}
  ]
end
```

And update our supervision tree to start Cowboy:

```elixir
# lib/my_app/application.ex

defmodule MyApp.Application do
  @moduledoc false

  use Application
  require Logger

  @impl true
  def start(_type, _args) do
    port = Application.fetch_env!(:my_app, :port)
    Logger.info("Starting Cowboy on port #{port}")

    children = [
      {Plug.Cowboy, scheme: :http, plug: MyApp.Plug, options: [port: port]}
    ]

    opts = [strategy: :one_for_one, name: MyApp.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
```

And finally let's implement `MyApp.Plug`:

```elixir
# lib/my_app/plug.ex

defmodule MyApp.Plug do
  use Plug.Builder

  plug(Plug.Logger)
  plug(:auth)
  plug(:static)
  plug(:not_found)

  defp auth(conn, _opts) do
    auth = Application.fetch_env!(:my_app, :auth)
    Plug.BasicAuth.basic_auth(conn, auth)
  end

  defp static(conn, _opts) do
    public_dir = Application.fetch_env!(:my_app, :public_dir)
    opts = Plug.Static.init(at: "/", from: public_dir)
    Plug.Static.call(conn, opts)
  end

  defp not_found(conn, _opts) do
    send_resp(conn, 404, "not found")
  end
end
```

We are ready to prepare our application for releases:

```
$ mix release.init
```

Let's edit the runtime configuration:

```elixir
# config/runtime.exs

import Config

config :my_app,
  port: String.to_integer(System.get_env("PORT", "8000")),
  auth: [
    username: System.get_env("AUTH_USERNAME", "hello"),
    password: System.get_env("AUTH_PASSWORD", "secret")
  ],
  public_dir: System.get_env("PUBLIC_DIR", "tmp/public")
```

We allow our app to be configured with environment variables but for convenience we also provide default values. We're ready to test our release!

```
$ MIX_ENV=prod mix release
(...)
* assembling my_app-0.1.0 on MIX_ENV=prod
* using config/runtime.exs to configure the release at runtime
* creating _build/prod/rel/my_app/releases/0.1.0/vm.args
* creating _build/prod/rel/my_app/releases/0.1.0/env.sh
* creating _build/prod/rel/my_app/releases/0.1.0/env.bat

Release created at _build/prod/rel/my_app!

    # To start your system
    _build/prod/rel/my_app/bin/my_app start

Once the release is running:

    # To connect to it remotely
    _build/prod/rel/my_app/bin/my_app remote

    # To stop it gracefully (you may also send SIGINT/SIGTERM)
    _build/prod/rel/my_app/bin/my_app stop

To list all commands:

    _build/prod/rel/my_app/bin/my_app
```

Let's run it! We will serve the `public` directory of the local repository we've created in the first section of the guide:

```
$ PORT=8000 PUBLIC_DIR=$HOME/acme/public _build/prod/rel/my_app/bin/my_app start
```

Since we've added the basic authentication, let's update the repository URL:

```
$ mix hex.repo set acme --url http://hello:secret@localhost:8000
```

And let's make sure everything works well by trying to retrieve the package one more time:

```
$ mix hex.package fetch decimal 2.0.0 --repo=acme
```

We're ready to put our application into a Docker container, let's define the Dockerfile:

```
FROM hexpm/elixir:1.11.2-erlang-23.1.2-alpine-3.12.1 as build

# install build dependencies
RUN apk add --no-cache git

# prepare build dir
WORKDIR /app

# install hex + rebar
RUN mix local.hex --force && \
    mix local.rebar --force

# set build ENV
ENV MIX_ENV=prod

# install mix dependencies
COPY mix.exs mix.lock ./
RUN mix deps.get --only $MIX_ENV
RUN mkdir config

# Uncomment if you'll use compile-time configuration
# # Dependencies sometimes use compile-time configuration. Copying
# # these compile-time config files before we compile dependencies
# # ensures that any relevant config changes will trigger the dependencies
# # to be re-compiled.
# COPY config/config.exs config/$MIX_ENV.exs config/
RUN mix deps.compile

# compile and build the release
COPY lib lib
RUN mix compile
# changes to config/runtime.exs don't require recompiling the code
COPY config/runtime.exs config/
COPY rel rel
RUN mix release

# Start a new build stage so that the final image will only contain
# the compiled release and other runtime necessities
FROM alpine:3.12.1 AS app
RUN apk add --no-cache openssl ncurses-libs

WORKDIR /app

RUN chown nobody:nobody /app

USER nobody:nobody

COPY --from=build --chown=nobody:nobody /app/_build/prod/rel/my_app ./

ENV HOME=/app

ENTRYPOINT ["bin/my_app"]
CMD ["start"]
```

Let's build our container and run it:

```
$ docker build . -t my_app
$ docker run --env PUBLIC_DIR=/public --env PORT=8000 -v $HOME/acme/public:/public -p 8000:8000 my_app
```

Notice how we're configuring the container with the appropriate environment variables, shared volumes, and published ports.

Let's test that everything works by once again fetching a package from our local repository:

```
$ mix hex.package fetch decimal 2.0.0 --repo=acme
```

We skipped on many details so if you want to learn more, definitely check out:

- https://hexdocs.pm/plug/Plug.Static.html
- https://hexdocs.pm/plug/Plug.BasicAuth.html
- https://hexdocs.pm/plug_cowboy/Plug.Cowboy.html
- https://hexdocs.pm/plug/https.html
- https://hexdocs.pm/phoenix/releases.html (even though we're not using Phoenix, our Docker deployment section was based on that guide!)
