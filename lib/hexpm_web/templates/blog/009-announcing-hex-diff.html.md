## Announcing Hex Diff

<div class="subtitle"><time datetime="2020-01-20T00:00:00Z">20 January, 2020</time> · by Johanna Larsson</div>

I'm incredibly excited to announce the new web-based Hex package differ: [diff.hex.pm](https://diff.hex.pm), maintained by the Hex team! This is the result of the issue on the [hex.pm Github repo](https://github.com/hexpm/hexpm/issues/848) and the discussion it started.

I'm super grateful to the Hex team, [Eric Meadows-Jönsson](https://twitter.com/emjii), [Wojtek Mach](https://twitter.com/wojtekmach), and [Todd Resudek](https://twitter.com/sprsmpl), for all their support and help in turning this idea into a live service.

### What does it do?

In short, you input any Hex package name and a version range, and it will generate a highlighted git diff for you, right there in your browser. Not only that, but you can also share the link to the diff, and even highlight a specific row. [Please take a moment to try it out!](https://diff.hex.pm)

### Why do we need it?

Across language ecosystems, package dependencies are becoming a more and more common vector of attack. Looking at npm or RubyGems, there are plenty of [examples of packages getting hijacked](https://snyk.io/blog/malicious-code-found-in-npm-package-event-stream/) and [malicious versions being uploaded](https://snyk.io/blog/code-execution-back-door-found-in-rubys-rest-client-library/). If you just update dependencies without checking them, you're not actually sure of what you're putting into production. And you can't trust what's on Github. An attacker can upload something to a registry without pushing it to Github. The only way to be sure is to look at what's actually on the registry.

Fortunately, the Hex team has been pro-active in managing this. With `hex` `0.20.0` a new command was added to mix: `mix hex.package diff package_name version_from..version_to`. It works by downloading the two selected package versions directly to your hard drive and then running `git diff` on them, finally outputting the result. If all it takes to audit dependency updates is scrolling through a diff that a tool generates for you, you're a lot more likely to do it. This is more convenient than manually downloading the packages, but when it comes to security, ease of use is everything.

So how can we make it better? Looking at other languages, there are some third-party services that provide web-based diffs, for example, there's one for [npm](https://diff.intrinsic.com/), and there's one for [RubyGems](https://diff.coditsu.io/). Inspired by the Ruby differ made by [Maciej Mensfeld](https://twitter.com/maciejmensfeld) and the mix command by [Wojtek Mach](https://twitter.com/wojtekmach), I made a [web-based differ for Hex](https://diff.jola.dev). I was excited to see people using it, but it didn't make sense to me for it to be a third-party service. If the intent is to create a trustworthy source of package changes, it needs to be managed by a trustworthy organization. Fortunately, the Hex team was really supportive of the idea!

When it's easy to work in a secure way, people are more likely to do it. This service, [diff.hex.pm](https://diff.hex.pm), is another step towards improving the security story for Elixir, by letting you generate diffs from any browser and share them as links. This also lends itself to automation: now you can generate these links programmatically and make dependency audits a part of your workflow. We hope this will inspire the community with lots of new ideas for security that doesn't slow you down.

### What's next?

The project is open-source, licensed under Apache 2.0, like Elixir itself. You'll find it under the `hexpm` organization [on Github](https://github.com/hexpm/diff). Please don't hesitate to share your ideas for improvements or additions!
