## Announcing hex_core

<div class="subtitle"><time datetime="2018-08-08T00:00:00Z">August 8, 2018</time> · by Wojtek Mach</div>

Today we are releasing the first version of hex_core, an Erlang library to interact with Hex.pm and other servers implementing Hex specifications.

Before talking about hex_core, let's ask a simple question: What is Hex? The short answer is, it's a package manager for the Erlang ecosystem. The long answer is that by Hex we may mean a few different things:
1. A set of specifications of building clients and servers that can interact with each other: <https://github.com/hexpm/specifications>
2. A server for hosting packages like the official server located at <https://hex.pm>
3. Clients for interacting with servers, e.g. [Hex](https://github.com/hexpm/hex) for Elixir and [rebar3_hex](https://github.com/tsloughter/rebar3_hex) for Erlang projects

The goal of hex_core is to be the reference implementation of Hex specifications used by Hex clients and servers.

As of this announcement the hex_core package itself is available on [Hex.pm](https://hex.pm/packages/hex_core).

### Usage in an Erlang project

1. Create a new project: `rebar3 new lib example`
2. Add `hex_core` to `rebar.config`:

   ```erlang
   {deps, [
     {hex_core, "0.1.0"}
   ]}
   ```
3. Start the shell to and count all packages published to Hex.pm:

   ```erlang
   $ rebar3 shell
   erl> inets:start(), ssl:start(),
   erl> Config = hex_core:default_config(),
   erl> {ok, {200, _, #{packages := Packages}}} = hex_repo:get_names(Config),
   erl> length(Packages).
   6764
   ```

### Usage in an Elixir project

1. Create a new project: `mix new example`
2. Add `hex_core` to `mix.exs`:

   ```elixir
   defp deps() do
     [{:hex_core, "~> 0.1"}]
   end
   ```

3. Start the shell to and search for all packages matching query "riak":

   ```elixir
   $ iex -S mix
   iex> :inets.start() ; :ssl.start()
   iex> config = :hex_core.default_config()
   iex> options = [sort: :downloads]
   iex> {:ok, {200, _, packages}} = :hex_api_package.search(config, "riak", options)
   iex> Enum.map(packages, & &1["name"])
   ["riak_pb", "riakc", ...]
   ```

See README at <https://github.com/hexpm/hex_core> for more usage examples.

### Future work

After the initial release we plan to work with the community to integrate hex_core into their projects and respond to feedback.

We will also be focused on releasing a minimal Hex server, built on top of hex_core, to be a starting point for people wanting
to run Hex on their own infrastructure. Stay tuned!
