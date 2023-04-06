## Hex v0.19 released

<div class="subtitle"><time datetime="2019-01-15T00:00:00Z">15 January, 2019</time> · by Eric Meadows-Jönsson</div>

The v0.19 release includes an important security fix to anyone accessing Hex repositories through a mirror. A bug has been found that would allow a malicious mirror to serve modified versions of Hex packages. [hex](https://github.com/hexpm/hex) versions `0.14.0` to `0.18.2` and [rebar3](https://github.com/erlang/rebar3) versions `3.7.0` to `3.7.5` are vulnerable. Make sure to update to hex `0.19.0` and rebar3 `3.8.0`.

The fix includes a backwards incompatible change to the registry format. All official repositories and mirrors have been updated, if you are using your own repository or mirror without updating the registry it will not be compatible with the latest Hex version. Ensure you are running up to date software or disable the security check by setting the environment variable `HEX_NO_VERIFY_REPO_ORIGIN=1`.

A full explanation of the security vulnerability will be posted in the future.

This release also includes improvements to the mix tasks `mix hex.config` and `mix hex.info`, and other bug fixes. For a full list of changes check the [release notes](https://github.com/hexpm/hex/releases/tag/v0.19.0).

Finally we would like to welcome [Todd Resudek](https://github.com/supersimple) as the newest member to the Hex team. Todd has been one of the most frequent contributors to Hex and it's great to now have him contribute in an official capacity.
