## Mirrors

Hex packages, the registry and other files are by distributed (mirrored) in various locations. The choice of mirror can be customized in Hex clients.

_Note_: By default, Fastly is used to deliver the files. Fastly distributes files geographically for low latency and fast downloads.

### Usage

To permanently select a mirror, simply run the following command in a shell session.

**Mix Example**: `$ mix hex.config mirror_url https://repo.hex.pm`

**Rebar3 Example**: Add to the global or a project's top level `rebar.config`, `{rebar_packages_cdn, "https://repo.hex.pm"}.`. For more information see rebar3's package support and configuration [documentation](https://rebar3.org/docs/configuration/dependencies/).

To temporarily select a mirror, Hex commands can be prefixed with an environment variable in the shell.

**Mix Example**: `$ HEX_MIRROR=https://repo.hex.pm mix deps.get`

**Rebar3 Example**: `$ HEX_CDN=https://repo.hex.pm rebar3 update`

### Available mirrors

| Provider | Location | URL | Official? |
| -------- | -------- | --- | --------- |
| Fastly   | Geographically distributed [*](https://www.fastly.com/network-map) | [https://repo.hex.pm](https://repo.hex.pm) | Yes |
| jsDelivr | Geographically distributed [*](http://www.jsdelivr.com/features/network-map) | [https://cdn.jsdelivr.net/hex](https://cdn.jsdelivr.net/hex) | No |
| UPYUN    | China    | [https://hexpm.upyun.com](https://hexpm.upyun.com) | No |
{: .table .table-striped}
