## Hex v2.4 released

<div class="subtitle"><time datetime="2026-03-31T00:00:00Z">31 March, 2026</time> · by Eric Meadows-Jönsson</div>

Hex 2.4 replaces password based authentication with an OAuth device flow and adds two-factor authentication support to the CLI. These changes significantly improve the security of publishing packages. We have also given the hex.pm website a new look.

### OAuth device flow

We have replaced password based authentication in the Hex CLI with an [OAuth 2.0 device authorization flow](https://datatracker.ietf.org/doc/html/rfc8628). When you run `mix hex.user auth` or any command that requires authentication you will be given a URL and a code to enter in your browser.

<img src="/images/blog/020_device_verification.png" srcset="/images/blog/020_device_verification.png 2x" alt="Device verification code">

Since the CLI authenticates through the browser it works regardless of the authentication method used on the website. We have also added GitHub as a sign in option, so together with the OAuth device flow you no longer need a password on your hex.pm account. This also opens the door for SSO and passkeys in the future.

The OAuth tokens are automatically refreshed and do not need to be manually managed. If a token cannot be refreshed you will be prompted to re-authorize through the browser.

Update Hex to the latest version by running `mix local.hex`. [Gleam](https://gleam.run) 0.15.0 has already been released with support for the new OAuth flow and we are hoping to have support in rebar3 soon. Once all CLI clients support OAuth we plan to deprecate password based authentication for CLIs.

### Two-factor authentication required for publishing

In 2020 we [added two-factor authentication](/blog/announcing-two-factor-auth) to hex.pm accounts as an optional feature. With Hex 2.4 we are taking the next step: 2FA must be enabled on your account for OAuth tokens to have write permissions. Without 2FA enabled, your token will only have read access and you will not be able to publish packages, manage owners, or perform other write operations.

<img src="/images/blog/020_device_authorize.png" srcset="/images/blog/020_device_authorize.png 2x" alt="Device authorization">

When running a write operation such as `mix hex.publish` or `mix hex.owner` you will be prompted for your authentication code. If you have not yet enabled 2FA you can do so in your [dashboard settings](/dashboard).

On the website we have also added a sudo mode that requires re-verifying with your 2FA code before performing sensitive actions such as managing API keys.

Supply chain attacks on package registries have become increasingly common and requiring a second factor for publishing and sensitive actions adds an important layer of protection for the ecosystem.

Looking ahead we want to add support for [trusted publishing](https://docs.pypi.org/trusted-publishers/) to allow packages to be published directly from CI without long-lived credentials. We are also planning package policies for organizations, such as requiring packages and versions to be pre-approved before they can be used. This would help mitigate attacks like the [recent axios compromise on npm](https://www.stepsecurity.io/blog/axios-compromised-on-npm-malicious-versions-drop-remote-access-trojan) where malicious versions were published to an existing package.

### Website redesign

As you may have noticed, the hex.pm website has a new look. Package pages now show the README directly, package search results show more information at a glance, and the dashboard has been reworked. Thanks to [Paulo Valim](https://www.linkedin.com/in/paulo-valim/) for implementing the new design.

For a full list of changes check the [release notes](https://github.com/hexpm/hex/releases/tag/v2.4.0).
