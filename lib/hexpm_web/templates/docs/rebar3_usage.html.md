## Usage

### Installation

Download [rebar3](https://s3.amazonaws.com/rebar3/rebar3), put it in your PATH and give it executable permissions. Now you can install the Hex plugin by adding `{plugins, [rebar3_hex]}.` to `~/.config/rebar3/rebar.config` and run all of its tasks.

### Defining dependencies

Hex packages as dependencies are supported by rebar3 even without the plugin. The hex plugin is only required for publishing an application as a hex package.

```erlang
{deps,[
  ranch,                  %% picks the highest available version
  {cowboy,"1.0.1"},       %% sets the version to use
  {uuid, {pkg, uuid_erl}} %% app under a different pkg name
]}.
```

For more information on dependencies and using rebar3 see the [rebar3 documentation](https://rebar3.org/docs/configuration/dependencies/).

### Fetching dependencies

First, update the package index with `rebar3 update`, you'll want to do this frequently to keep up to date. The default package index is stored in `~/.cache/rebar3/hex/default/packages.idx`. Running `rebar3 compile` will automatically fetch any missing dependencies and build them under `_build/default/lib`. Packages are cached to `~/.cache/rebar3/hex/default/packages`.
