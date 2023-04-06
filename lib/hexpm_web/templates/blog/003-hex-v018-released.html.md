## Hex v0.18 released

<div class="subtitle"><time datetime="2018-07-05T00:00:00Z">July 5, 2018</time> · by Eric Meadows-Jönsson</div>

The v0.18 release includes improvements to API key handling and workflows when using continuous integration.

### API keys

When authenticating with `mix hex.user auth` we now generate two API keys instead of single one. One key is unencrypted with read access and the other is encrypted with your local password and has full read/write access to the API. Hex encrypts the API key for security reasons, for example you cannot run `mix hex.publish` without providing a password, but it meant that commands such `mix hex.search` required password which felt unnecessary. Now commands that don't make any changes will not require a password.

Additionally, we generate a single key that gives access to all your organization repositories, instead of one key for each repository. It also has the added benefit that you don't have to reauthenticate if you are added to a new organization.

We have also added support for keys owned directly by an organization instead of a specific user, these keys can be accessed through `mix hex.organization` and through the [organization dashboard](/dashboard). This is useful when generating keys for a CI environment, previously when personal keys were used, a person leaving an organization or revoking the key could negatively affect CI workflow.

### Improvements to continuous integration workflows

The `HEX_API_KEY` environment variable has been introduced to be able run commands that require an authentication without having to authenticate manually with `mix hex.user auth` which has user input prompts. The key set with `HEX_API_KEY` can be generated with `mix hex.user key generate` or `mix hex.organization key ORGANIZATION generate`. It also makes it possible to run commands such as `mix hex.publish` without being prompted for a password.

By passing the `--yes` flag to `mix hex.publish` you can publish your package (together with `HEX_API_KEY`) without any confirmation prompts. This allows you to publish your package as part of your CI build process. Keep in mind that this will publish the package even if there are warnings from Hex and that you cannot inspect the compiled package contents before publishing so you should use this option with care.

### Summing up

This release focused on workflow improvements when working in CI environments and running commands that requires authentication. Users that have private packages will have better security because they can use specialized keys for their organizations.

The work of moving functionality from the Hex client to [hex_core](https://github.com/hexpm/hex_core) is ongoing. hex_core is an effort started by Hex team member Wojtek Mach, the idea is to move the core functionality needed to create a Hex package manager client to a common Erlang library. This reduces duplicate development effort and will allow tools such as [rebar3](https://rebar3.org/) and [erlang.mk](https://erlang.mk/) to stay up to date with the latest changes and improvements to Hex.

Next up for the core team is releasing private HexDocs and adding annual billing for organizations. The full list of changes for Hex v0.18.0 is available in our [release notes](https://github.com/hexpm/hex/releases/tag/v0.18.0).
