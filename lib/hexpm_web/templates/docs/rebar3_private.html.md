## Private packages and organizations

Starting with rebar3 version 3.7.0, multiple Hex repositories (or indexes) can be used at the same time. Repositories are declared in an ordered list, from highest priority to lowest priority.

When looking for a package, repositories are going to be traversed in order. As soon as one of the packages fits the description, it is downloaded. The hashes for each found packages are kept in the project's lockfile, so that if the order of repositories changes and some of them end up containing conflicting packages definitions for the same name and version pairs, only the expected one will be downloaded.

This allows the same mechanism to be used for both mirrors, private repositories (as provided by hex.pm), and self-hosted indexes.

### Publishing or using a private package

For publishing or using a private repository you must use the [rebar3_hex](https://github.com/erlef/rebar3_hex) plugin to authenticate, `rebar3 hex organization auth` after declaring the private organization (defined as `parent_repo:organization`, see the example is below) as a repository in the rebar3 config. Authenticating then creates a separate config file `~/.config/rebar3/hex.config` storing the keys.


```erlang
{repos, [
  #{name => <<"hexpm:private_org">>}
]}.
```

To publish to a private repository, use `rebar3 hex publish -r hexpm:private_org`.


### Authenticating on CI and build servers
You can generate organizations keys on your organization's [dashboard](/dashboard).

```nohighlight
$ rebar3 hex organization auth hexpm:private_org -k <key>
```

This can then be used to fetch packages on your CI servers without requiring manual authentication with username and password.
