## Announcing Two-factor Auth

<div class="subtitle"><time datetime="2020-05-05T00:00:00Z">5 May, 2020</time> · by Todd Resudek</div>

Today we launched the option for two-factor authentication on hex.pm. Starting today, you can activate 2FA via the hex.pm dashboard. Many thanks to community contributors [Bryan Paxton](https://twitter.com/starbelly9) and [Jeffrey Liao](https://github.com/jeffreyplusplus) for their work on this project.

### Benefits

Activating 2FA on your account will make it more secure. If a bad actor were to gain access to your account, they could publish malicious packages under your name. Adding a second authentication greatly reduces this risk.

### Will this be required?

At this point we do not anticipate making 2FA a requirement for accounts. However, you are responsible for your own account and we hope you take steps to mitigate any potential breach of it.

### Compatibility

Two-factor auth has been tested with most popular applications. This includes Authy, Google Authenticator, Microsoft Authenticator, and 1Password. If you have a preferred app that you find does not work, please report it to us by emailing [support@hex.pm](mailto:support@hex.pm).

### What's next?

The next project is to also offer 2FA in the Hex CLI. I expect that work to begin in earnest this summer.
