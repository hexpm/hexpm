# Package metadata

The metadata can be expressed in many media types, in the package tarball it as an "Erlang term file" that can be read with [`file:consult/1`][]. This specification describes the format used in the package tarball.

## Types

All types listed here are Erlang terms.

  + `string` - A UTF-8 encoded Erlangbinary
  + `boolean` - A boolean (`true` or `false`)
  + `list(Inner)` - A list with an `Inner` type
  + `proplist(Key => Value)` - A list with two element tuples where the first element is of type `Key` and the second `Value`

Proplists are normally generic in the sense that they can have any values for keys, but they can also allow only specific keys: `proplist(...)` where the keys will be listed in relation to the type.

## Format

All keys are strings.

  + `name (string)`
  
    Package name

  + `version (string)`
  
    Release version, required to be a [Semantic Version][]

  + `app (string)`
    
    OTP application name, usually the same name as the package but can differ

  + `description (string)`
    
    Package description, recommended to be a single paragraph

  + `files (list(string))`

    Files in the package tarball contents

  + `licenses (list(string))`

    The library's licenses

  + `links (proplist(string => string))`

    Links related to the package where the key is the link name and the value is the URL

  + `requirements (proplist(string => proplist(...)))`

    All dependencies of the package where the key is the dependent name

    + `app (string)`

      OTP application name, usually the same name as the package

    + `optional (boolean)`

      If the package is required or not

    + `requirement (string)`

      [Version requirement][] on the dependent

  + `build_tools (list(string))`

      Names of build tools that can build the package

### Optional dependencies

An optional dependency will only be used if a package higher up the dependency chain also depends on it (only if that the dependency is not defined as optional as well).

#### Example

The package ecto have an optional dependency postgrex, if a project X depends on ecto and postgrex both dependencies will be used and ecto's version requirement on postgrex has to be satisfies. But if project X only depends on ecto the postgrex package can be ignored.

[`file:consult/1`]: http://www.erlang.org/doc/man/file.html#consult-1
[Semantic Version]: http://semver.org/
[Version requirement]: http://elixir-lang.org/docs/stable/elixir/Version.html
