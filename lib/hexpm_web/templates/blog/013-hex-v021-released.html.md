## Hex v0.21 released

<div class="subtitle"><time datetime="2021-01-15T00:00:00Z">15 January, 2021</time> · by Wojtek Mach</div>

Hex v0.21 adds registry self-hosting, diff & dependencies improvements, `mix hex.sponsor` task, and more!

### Self-hosting

Hex ships with a new [`mix hex.registry`](https://hexdocs.pm/hex/Mix.Tasks.Hex.Registry.html) task to easily build a local Hex registry.
See the new [self-hosting guide](https://hex.pm/docs/self_hosting) for more information.

### Diff & dependencies

The new release also brings many improvements to better understand and manage dependencies in your Mix projects.

`mix hex.outdated` now makes it easy to see what changed in your dependencies between the versions you are using and the latest ones, it outputs a link which will show you a list of diffs:

```
$ mix hex.outdated
```

![mix hex.outdated output](/images/blog/013_hexoutdated.png)

Navigating to http://hex.pm/l/T16Wu will show you:

![diff.hex.pm output](/images/blog/013_hexdiff.png)

`mix hex.package diff` can now be used to diff the currently used version (in `mix.lock`) against an arbitrary version:

```
$ mix hex.package diff ecto 3.5.1
(...)
@@ -1,15 +1,16 @@
 defmodule Ecto.MixProject do
   use Mix.Project

-  @version "3.5.0"
+  @version "3.5.1"
(...)
```

When running outside of Mix project, it now allows a more compact version range specification:

```
$ mix hex.package diff ecto 3.5.{0,1}
(...)
@@ -1,15 +1,16 @@
 defmodule Ecto.MixProject do
   use Mix.Project

-  @version "3.5.0"
+  @version "3.5.1"
(...)
```

Thanks [@halostatue](https://github.com/halostatue), [@RyanSiu1995](https://github.com/RyanSiu1995), and [@xinz](https://github.com/xinz) for working on some of these enhancements!

### Sponsorships

Hex now makes it easy to find packages with sponsorships. Run the command below to find such dependencies in your current project and here is how the output might look like:

```
$ mix hex.sponsor
Dependency  Sponsorship
cowboy      https://github.com/sponsors/essen
oban        https://getoban.pro
```

If you want your project to be listed, add a `"Sponsor"` link in your `mix.exs` (or in `rebar.config`, etc):

```elixir
links: %{
  "GitHub" => "https://github.com/sorentwo/oban",
  "Sponsor" => "https://getoban.pro"
}
```

Thanks [@philss](https://github.com/philss) for working on this!

### `mix hex.publish --replace`

First, a quick reminder of Hex.pm package update policy from <https://hex.pm/docs/faq>:

> The Hex repository is immutable (...)
>
> There are exceptions to the immutability rule, a package can be changed or unpublished within 60 minutes of the package version release or within 24 hours of initial release of the package.

Now when attempting to re-publish an existing version, you'll need to explicitly pass a `--replace` flag.

Worth mentioning that there's no re-publishing time window on [Hex.pm Private Packages](https://hex.pm/docs/private) and so the `--replace` option is particularly useful there.

### 'latest' branch

The <https://github.com/hexpm/hex> repository now maintains a `latest` branch which means you can install Hex via:

```
$ mix archive.install github hexpm/hex branch latest
```

This is useful when you have problems (e.g. HTTP errors) with using the default installation method of running `$ mix local.hex`.

### Other changes

Hex v0.21 brings many other improvements and bug fixes, for a full list of changes see the [CHANGELOG](https://github.com/hexpm/hex/blob/v0.21.0/CHANGELOG.md). Thank you to all contributors who made that happen!
