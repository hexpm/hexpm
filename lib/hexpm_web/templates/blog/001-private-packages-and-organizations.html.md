## Private packages and organizations

<div class="subtitle"><time datetime="2017-08-28T00:00:00Z">August 28, 2017</time> · by Eric Meadows-Jönsson</div>

We are announcing the addition of private packages on Hex.pm. With private packages you can publish
packages to Hex.pm that only your organization members can access and download. With your organization
you get a repository namespace on Hex.pm so that your private packages will not conflict with packages
in the global, public repository. Go check out the [private package](/docs/private) documentation to
learn exactly how it works.

This will be a paid feature based on the number of members in your organization. We have sponsorships
from Plataformatec and Fastly to help with some of the hosting and CDN costs, but there are still
associated costs with running Hex.pm that hopefully this can help offset. Furthermore, private packages
provide a different set of features and require a private infrastructure that introduces complexity and
costs more to maintain.

Pushing public packages will of course stay free and if you run an open source project
that needs private packages you can contact us to get free access. The revenue from private
packages will help us increase the quality of both public and private services.

This feature is currently in beta and there are still missing features, most notably billing and documentation
hosting on hexdocs.pm. If you want to try it or help beta test private packages, please fill out the
[sign up form](/dashboard/orgs) to request access.

Even though we are introducing paid features everything around Hex will stay open source, the only closed
source part will be the billing service.
