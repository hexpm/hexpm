## Hex v1.0 released and the future of Hex

<div class="subtitle"><time datetime="2021-12-13T00:00:00Z">13 December, 2021</time> · by Eric Meadows-Jönsson</div>

We just released Hex 1.0.0 with no major changes compared to the last release 0.21.0 and we will soon release Hex 2.0.0, again with no major changes. Let's talk about why we are doing this and what Hex being version 1.0.0 or 2.0.0 means.

### Ensuring backwards compatibility

Backwards compatibility in a package manager is very important. Hex has so far maintained backwards compatibility with Elixir 1.0.0 with every new release of Hex. The reason for this is because Hex needs to be kept up to date to continue working, otherwise things like certificates or changing APIs means things will break. If Hex stopped working on a given Elixir version it would effectively mean that the Elixir version becomes unusuable for any real development. So far we have kept a single development track for Hex, meaning new features and security fixes are applied to the same branch.

By releasing Hex 1.0.0 we are committing to continue supporting older Elixir versions as long as is feasibly possible.

### Hex v2.0

But supporting older Elixir versions has limited our feature development, we cannot use common Elixir constructs that we take for granted today such as `with` or any dependencies that require a newer version of Elixir than 1.0.0.

The Hex team is intending to continue supporting Elixir 1.0.0 for as long as is feasible in the Hex 1.0 release track, but 1.0 will only get security fixes and changes that are critical to it continue functioning.

Soon we will also release Hex 2.0.0 which will drop support for Elixir versions older than 1.5.0 and get all future feature development. Other than the quality of life improvement for the maintainers, we will also be able to ship a completely rewritten version solver and a new HTTP client that should give improved performance and improvements for users on slower or unreliable network connections. We will talk more about those changes as they get closer to release.
