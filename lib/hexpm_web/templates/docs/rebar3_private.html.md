## Private packages and organizations

Starting with rebar3 version 3.7.0, multiple Hex repositories (or indexes) can be used at the same time. Repositories are declared in an ordered list, from highest priority to lowest priority.

When looking for a package, repositories are going to be traversed in order. As soon as one of the packages fits the description, it is downloaded. The hashes for each found packages are kept in the project's lockfile, so that if the order of repositories changes and some of them end up containing conflicting packages definitions for the same name and version pairs, only the expected one will be downloaded.

This allows the same mechanism to be used for both mirrors, private repositories (as provided by hex.pm), and self-hosted indexes.

### Publishing or using a private package

For publishing or using a private repository you must use the [rebar3_hex](https://github.com/tsloughter/rebar3_hex) plugin to authenticate, `rebar3 hex auth`. This creates a separate config file `~/.config/rebar3/hex.config` storing the keys.


```elixir
{repos, [
   %% A self-hosted repository that allows publishing may look like this
   #{name => <<"my_hexpm">>,
     api_url => <<"https://localhost:8080/api">>,
     repo_url => <<"https://localhost:8080/repo">>,
     repo_public_key => <<"-----BEGIN PUBLIC KEY-----
     ...
     -----END PUBLIC KEY-----">>
   },
   %% A mirror looks like a standard repo definition, but uses the same
   %% public key as hex itself. Note that the API URL is not required
   %% if all you do is fetch information
   #{name => <<"jsDelivr">>,
     repo_url => <<"https://cdn.jsdelivr.net/hex">>,
     ...
    },
    %% If you are a paying hex.pm user with a private organisation, your
    %% private repository can be declared as:
    #{name => <<"hexpm:private_repo">>}
    %% and authenticate with the hex plugin, rebar3 hex auth
]}.

%% The default Hex config is always implicitly present.
%% You could however replace it wholesale by using a 'replace' value,
%% which in this case would redirect to a local index with no signature
%% validation being done. Any repository can be replaced.
{repos, replace, [
   #{name => <<"hexpm">>,
     api_url => <<"https://localhost:8080/api">>,
     repo_url => <<"https://localhost:8080/repo">>,
     ...
    }               
]}.
```
