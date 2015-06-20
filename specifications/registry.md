# Registry

The registry is an ETS table serialized with [`ets:tab2file/1`][]. Clients
consuming the registry should always match on only the front of a list

Below is the layout of the table.

  * `{'$$version$$', Version}` - the registry version
    - Version: integer, incremented on breaking changes

  * `{Package, [Versions]}` - all releases of a package
    - Package: binary string
    - Versions: list of binary string [semver][] versions

  * `{{Package, Version}, [Deps, Checksum, BuildTools]}` - a package release's dependencies
    - Package: binary string
    - Version: binary string [semver][] version
    - Deps: list of dependencies [Dep, ...]
      - Dep: [Name, Requirement, Optional, App]
        - Name: binary package name
        - Requirement: binary Elixir [version requirement][]
        - Optional: boolean, true if it's an optional dependency
        - App: binary, OTP application name
    - Checksum: binary hex encoded sha256 checksum of package, see below
    - BuildTools: list of binary string build tool names

## Links

[`ets:tab2file/1`]: http://www.erlang.org/doc/man/ets.html#tab2file-2
[semver]: http://semver.org/
[version requirement]: http://elixir-lang.org/docs/stable/elixir/Version.html
