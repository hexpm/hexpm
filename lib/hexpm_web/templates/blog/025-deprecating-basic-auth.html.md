## Deprecating Basic Authentication on the API

<div class="subtitle"><time datetime="2026-07-28T00:00:00Z">28 July, 2026</time> · by Eric Meadows-Jönsson</div>

Hex.pm will disable HTTP Basic authentication on the API. Basic auth sends a
username and password on every request and has no way to carry a second factor,
which blocks us from requiring two-factor authentication for API access. To move
forward on that goal, we are phasing Basic auth out of the API entirely.

Throughout October 2026, from the 1st through the 31st, we will run a month
of increasing brown-outs during which Basic auth requests to the API will be
rejected. On **1 November 2026** Basic authentication on the API will be
disabled permanently.

### Alternatives

If you or your tooling still authenticates to the API with a username and
password, switch to one of the supported alternatives before the brown-outs
begin.

  * **OAuth (recommended).** Hex.pm supports the OAuth 2.0 Device Authorization
    Grant for CLI tools and full OAuth client support for web applications. The
    official Hex CLI already uses the Device Grant for interactive login. OAuth
    is the recommended option because it integrates with two-factor
    authentication and keeps long-lived credentials off developer machines.
  * **API keys.** Both user API keys and organization API keys can be created
    from the Hex.pm dashboard and used in the `Authorization` header. Use
    organization keys for CI and other shared automation so access can be
    scoped and revoked independently of any individual account.

### Why this is happening

Hex.pm requires two-factor authentication for sensitive account actions and for
publishing, but Basic authentication on the API has always been a gap in that
policy. A password alone is enough to authenticate an API request, regardless of
whether the account has 2FA enabled. Removing Basic auth from the API closes
that gap and lets us enforce 2FA consistently across every way an account can be
used.

### Brown-out schedule

During the windows below, API requests authenticated with HTTP Basic auth will
be rejected with `401 Unauthorized`. Requests using OAuth tokens or API keys are
unaffected. All times are in UTC.

The window start times rotate each day so that no recurring job, whether it
runs hourly, every six hours, nightly, or weekly, consistently avoids or
consistently hits the brown-out. The window length grows every week so the
disruption escalates gradually, and even the final week keeps meaningful gaps
between windows so a broken deploy has room to recover before the permanent
cutover.

**Week 1 (1 - 7 October):** two one-hour windows per day.

  * **2026-10-01:** 00:00 - 01:00 and 12:00 - 13:00
  * **2026-10-02:** 05:00 - 06:00 and 17:00 - 18:00
  * **2026-10-03:** 10:00 - 11:00 and 22:00 - 23:00
  * **2026-10-04:** 03:00 - 04:00 and 15:00 - 16:00
  * **2026-10-05:** 08:00 - 09:00 and 20:00 - 21:00
  * **2026-10-06:** 01:00 - 02:00 and 13:00 - 14:00
  * **2026-10-07:** 06:00 - 07:00 and 18:00 - 19:00

**Week 2 (8 - 14 October):** two two-hour windows per day.

  * **2026-10-08:** 00:00 - 02:00 and 12:00 - 14:00
  * **2026-10-09:** 05:00 - 07:00 and 17:00 - 19:00
  * **2026-10-10:** 10:00 - 12:00 and 22:00 - 00:00
  * **2026-10-11:** 03:00 - 05:00 and 15:00 - 17:00
  * **2026-10-12:** 08:00 - 10:00 and 20:00 - 22:00
  * **2026-10-13:** 01:00 - 03:00 and 13:00 - 15:00
  * **2026-10-14:** 06:00 - 08:00 and 18:00 - 20:00

**Week 3 (15 - 21 October):** two four-hour windows per day.

  * **2026-10-15:** 00:00 - 04:00 and 12:00 - 16:00
  * **2026-10-16:** 03:00 - 07:00 and 15:00 - 19:00
  * **2026-10-17:** 06:00 - 10:00 and 18:00 - 22:00
  * **2026-10-18:** 01:00 - 05:00 and 13:00 - 17:00
  * **2026-10-19:** 04:00 - 08:00 and 16:00 - 20:00
  * **2026-10-20:** 07:00 - 11:00 and 19:00 - 23:00
  * **2026-10-21:** 02:00 - 06:00 and 14:00 - 18:00

**Week 4 (22 - 28 October):** two eight-hour windows per day, still leaving
about eight hours per day when Basic auth continues to work.

  * **2026-10-22:** 00:00 - 08:00 and 12:00 - 20:00
  * **2026-10-23:** 03:00 - 11:00 and 15:00 - 23:00
  * **2026-10-24:** 01:00 - 09:00 and 13:00 - 21:00
  * **2026-10-25:** 04:00 - 12:00 and 16:00 - 00:00
  * **2026-10-26:** 02:00 - 10:00 and 14:00 - 22:00
  * **2026-10-27:** 00:00 - 08:00 and 12:00 - 20:00
  * **2026-10-28:** 03:00 - 11:00 and 15:00 - 23:00

**Final stretch (29 - 31 October):** two ten-hour windows per day, leaving
about two hours per half-day to recover before the permanent cutover.

  * **2026-10-29:** 00:00 - 10:00 and 12:00 - 22:00
  * **2026-10-30:** 02:00 - 12:00 and 14:00 - 00:00
  * **2026-10-31:** 01:00 - 11:00 and 13:00 - 23:00

From **2026-11-01** onwards, HTTP Basic authentication on the Hex.pm API is
disabled permanently.

### What to do now

Audit any tooling or scripts that talk to the Hex.pm API with a username and
password, and switch them to OAuth or an API key before 1 October. If you
maintain a client library or CI integration that still exposes Basic auth to
users, please plan a release that moves it to one of the supported alternatives.

If you run into problems migrating, reach out at
[support@hex.pm](mailto:support@hex.pm).
