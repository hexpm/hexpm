## Usage

### Installation

Mix will automatically prompt you whenever there is a need to use Hex. In case you want to manually install or update hex, simply run `$ mix local.hex`.

### Defining dependencies

Hex integrates with Mix's dependency handling. Dependencies are defined in Mix's format and all the ordinary Mix dependency commands work. In particular, all dependencies without a SCM (`:git` or `:path`) are automatically handled by Hex. Hex dependencies are defined in the following format:

`{:package, requirement}`

The version requirement specify which versions of the package you allow. The formats accepted for the requirement are documented in the [Version module](https://hexdocs.pm/elixir/Version.html). Below is an example `mix.exs` file.

```elixir
defmodule MyProject.MixProject do
  use Mix.Project

  def project() do
    [
      app: :my_project,
      version: "0.0.1",
      elixir: "~> 1.0",
      deps: deps(),
    ]
  end

  def application() do
    []
  end

  defp deps() do
    [
      {:ecto, "~> 2.0"},
      {:postgrex, "~> 0.8.1"},
      {:cowboy, github: "ninenines/cowboy"},
    ]
  end
end
```

For more information about dependencies see the [Mix documentation](https://hexdocs.pm/mix/Mix.Tasks.Deps.html#content).

### Options

<dl class="dl-horizontal">
  <dt><code>:hex</code></dt>
  <dd>The name of the package. Defaults to the dependency application name.</dd>
  <dt><code>:repo</code></dt>
  <dd>The repository to fetch the package from, the repository needs to be configured with the <code>mix hex.repo</code> task. Defaults to the global <code>"hexpm"</code> repository.</dd>
  <dt><code>:organization</code></dt>
  <dd>The organization repository to fetch the package from, the organization needs to be configured with the <code>mix hex.organization</code> task.</dd>
</dl>

### Fetching dependencies

`$ mix deps.get` will fetch dependencies that were not already fetched. Dependency fetching is repeatable, Mix will lock the version of a dependency in the lockfile to ensure that all developers will get the same version (always commit `mix.lock` to version control). `$ mix deps.update` will update the dependency and write the updated version to the lockfile.

When Mix tries to fetch Hex packages that are not locked, dependency resolution will be performed to find a set of packages that satisfies all version requirements. The resolution process will always try to use the latest version of all packages. Because of the nature of dependency resolution Hex may sometimes fail to find a compatible set of dependencies. This can be resolved by unlocking dependencies with `$ mix deps.unlock`, more unlocked dependencies give Hex a larger selection of package versions to work with.
