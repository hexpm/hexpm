## Private packages

*Private packages are currently in beta, email [support@hex.pm](mailto:support@hex.pm) to request access.*

Private packages are namespaced under a repository. To administer any repositories you are a member of go to the [dashboard](/dashboard).

### Add a repository to mix

Before you can fetch packages from a repository it needs to be added to mix. Run the following command to do so:

```nohighlight
$ mix hex.repo add hexpm:myrepo
```

To run this command you need to have an authenticated user on your local machine, run `$ mix hex.user register` to register or `$ mix hex.user auth` to authenticate with an existing user.

### Publishing a private package

To publish a package simply add the `--repo` flag to the `$ mix hex.publish --repo myrepo` command. You can also configure a package to belong to a specific repository, add the `repo: "myrepo"` option to the package configuration:

```elixir
defp package() do
  [
    repo: "myrepo",
    ...
  ]
end
```

*You can publish documentation for private packages, but this feature is still in beta and they will not be visible on [hexdocs.pm](https://hexdocs.pm) currently.*

### Using private packages as dependencies

A private package can only depend on packages from its own repository and from the global `"hexpm"` repository where all public packages belong. You specify from which repository a package should be fetched with the `:repo` option on the dependency declaration, if this option is not included it is assumed the package belongs to the global repository. For example:

```elixir
defp deps() do
  [
    # This package will be fetched from the global repository
    {:ecto, "~> 2.0"},
    # This package will be fetched from the myrepo repository
    {:secret, "~> 1.0", repo: "myrepo"},
  ]
end
```
