## Private packages and organizations

With an organization you can publish and fetch private packages from Hex.pm and you can control exactly which users have access to the packages. To administer any organizations you are a member of go to the [dashboard](/dashboard). Go to the [sign up form](/dashboard/orgs) to create an organization.

### Add an organization to Mix

The organization's packages are namespaced under the organization's repository. Only members of the organization have access to the repository's packages, to get access in Mix you need to authorize the organization with the `mix hex.organization` task. Run the following command to do so:

```nohighlight
$ mix hex.organization auth acme
```

To run this command you need to have an authenticated user on your local machine, run `$ mix hex.user register` to register or `$ mix hex.user auth` to authenticate with an existing user.

### Publishing a private package

To publish a package simply to your organization add the `--organization` flag to the `$ mix hex.publish --organization acme` command. You can also configure a package to belong to a specific organization, add the `organization: "acme"` option to the package configuration:

```elixir
defp package() do
  [
    organization: "acme",
    ...
  ]
end
```

### Using private packages as dependencies

A private package can only depend on packages from its own repository and from the global `"hexpm"` repository where all public packages belong. You specify a package should be fetched from a specific organization's repository with the `:organization` option on the dependency declaration, if this option is not included it is assumed the package belongs to the global repository. For example:

```elixir
defp deps() do
  [
    # This package will be fetched from the global repository
    {:ecto, "~> 2.0"},
    # This package will be fetched from the acme organization's repository
    {:secret, "~> 1.0", organization: "acme"},
  ]
end
```

### Authenticating on CI and build servers

You can generate repository authentication keys manually with the `mix hex.organization key` task. This can then be used to fetch packages on your CI servers without requiring manual authentication with username and password.

Run the following command on your local machine:

```nohighlight
$ mix hex.organization key acme generate
Passphrase: ...
126d49fb3014bd26457471ebae97c625
```

You can also generate organizations keys on your organization's [dashboard](/dashboard).

Copy the returned hash and authenticate with it on your build server:

```nohighlight
$ mix hex.organization auth acme --key 126d49fb3014bd26457471ebae97c625
```
