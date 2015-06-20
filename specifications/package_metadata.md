# Package metadata

    name          :: binary
    version       :: binary
    app           :: binary
    description   :: binary
    files         :: list(binary)
    licenses      :: list(binary)
    links         :: proplist(binary => binary)
    requirements  :: proplist(binary => proplist("optional" => boolean, "requirement" => binary))

version is required to be semver
requirement string is documented on http://elixir-lang.org/docs/stable/elixir/Version.html

# Release metadata

    build_tools   :: list(binary)
