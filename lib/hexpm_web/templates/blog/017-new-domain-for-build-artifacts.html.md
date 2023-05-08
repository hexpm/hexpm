## New domain for build artifacts

<div class="subtitle"><time datetime="2023-05-08T00:00:00Z">8 May, 2023</time> · by Eric Meadows-Jönsson</div>

The Hex team builds and hosts precompiled versions of Elixir, Erlang/OTP, and Hex itself. These are currently hosted on https://repo.hex.pm but will be moved to https://builds.hex.pm. (You can read more about the builds on https://github.com/hexpm/bob).

The affected URLs are under https://repo.hex.pm/builds/ and https://repo.hex.pm/installs/, and will be moved to https://builds.hex.pm/builds/ https://builds.hex.pm/installs/ respectively.

The transition period will be over 3 months with increasing "brownout" periods where repo.hex.pm will redirect to builds.hex.pm. After the 3 month period the redirect will become permanent.

If you have tooling that uses builds from Hex, you should update it to use the new builds.hex.pm domain. If your download tool can follow HTTP redirects you will be unaffected by the change to the new domain, you can test if redirects are handled correctly by using the https://repo.hex.pm/redirect/builds URL.

[Elixir](https://github.com/elixir-lang/elixir/), [setup-beam](https://github.com/erlef/setup-beam), and [asdf-elixir](https://github.com/asdf-vm/asdf-elixir) have already been updated to use builds.hex.pm. Past versions of Elixir will continue to be able to install Hex since Elixir will follow redirects. Past versions of setup-beam did not follow redirects will not work but if you use the tag `v1` you will get automatic updates. Past versions of asdf-elixir also did not follow redirects and will stop working unless you update by running `asdf plugin-update elixir`.

### Brownout schedule

During the following dates and times there will be be temporary redirects from https://repo.hex.pm/builds/ to https://builds.hex.pm/builds/ and https://repo.hex.pm/installs/ to https://builds.hex.pm/installs/.

The first month after this month there will be no redirects. The second month there will be two distinct hours of redirects each day separated by 12 hours. The third month there will be six hours of redirects each day. After that the redirect will be permanent.

All times are in UTC.

  * **2023-06-09:** 00:00 - 01:00 and 12:00 - 13:00
  * **2023-06-10:** 01:00 - 02:00 and 13:00 - 14:00
  * **2023-06-11:** 02:00 - 03:00 and 14:00 - 15:00
  * **2023-06-12:** 03:00 - 04:00 and 15:00 - 16:00
  * **2023-06-13:** 04:00 - 05:00 and 16:00 - 17:00
  * **2023-06-14:** 05:00 - 06:00 and 17:00 - 18:00
  * **2023-06-15:** 06:00 - 07:00 and 18:00 - 19:00
  * **2023-06-16:** 07:00 - 08:00 and 19:00 - 20:00
  * **2023-06-17:** 08:00 - 09:00 and 20:00 - 21:00
  * **2023-06-18:** 09:00 - 10:00 and 21:00 - 22:00
  * **2023-06-19:** 10:00 - 11:00 and 22:00 - 23:00
  * **2023-06-20:** 11:00 - 00:00 and 23:00 - 12:00
  * **2023-06-21:** 00:00 - 01:00 and 12:00 - 13:00
  * **2023-06-22:** 01:00 - 02:00 and 13:00 - 14:00
  * **2023-06-23:** 02:00 - 03:00 and 14:00 - 15:00
  * **2023-06-24:** 03:00 - 04:00 and 15:00 - 16:00
  * **2023-06-25:** 04:00 - 05:00 and 16:00 - 17:00
  * **2023-06-26:** 05:00 - 06:00 and 17:00 - 18:00
  * **2023-06-27:** 06:00 - 07:00 and 18:00 - 19:00
  * **2023-06-28:** 07:00 - 08:00 and 19:00 - 20:00
  * **2023-06-29:** 08:00 - 09:00 and 20:00 - 21:00
  * **2023-06-30:** 09:00 - 10:00 and 21:00 - 22:00
  * **2023-07-01:** 10:00 - 11:00 and 22:00 - 23:00
  * **2023-07-02:** 11:00 - 00:00 and 23:00 - 12:00
  * **2023-07-03:** 00:00 - 01:00 and 12:00 - 13:00
  * **2023-07-04:** 01:00 - 02:00 and 13:00 - 14:00
  * **2023-07-05:** 02:00 - 03:00 and 14:00 - 15:00
  * **2023-07-06:** 03:00 - 04:00 and 15:00 - 16:00
  * **2023-07-07:** 04:00 - 05:00 and 16:00 - 17:00
  * **2023-07-08:** 05:00 - 06:00 and 17:00 - 18:00
  * **2023-07-09:** 00:00 - 06:00
  * **2023-07-10:** 06:00 - 12:00
  * **2023-07-11:** 12:00 - 18:00
  * **2023-07-12:** 18:00 - 00:00
  * **2023-07-13:** 00:00 - 06:00
  * **2023-07-14:** 06:00 - 12:00
  * **2023-07-15:** 12:00 - 18:00
  * **2023-07-16:** 18:00 - 00:00
  * **2023-07-17:** 00:00 - 06:00
  * **2023-07-18:** 06:00 - 12:00
  * **2023-07-19:** 12:00 - 18:00
  * **2023-07-20:** 18:00 - 00:00
  * **2023-07-21:** 00:00 - 06:00
  * **2023-07-22:** 06:00 - 12:00
  * **2023-07-23:** 12:00 - 18:00
  * **2023-07-24:** 18:00 - 00:00
  * **2023-07-25:** 00:00 - 06:00
  * **2023-07-26:** 06:00 - 12:00
  * **2023-07-27:** 12:00 - 18:00
  * **2023-07-28:** 18:00 - 00:00
  * **2023-07-29:** 00:00 - 06:00
  * **2023-07-30:** 06:00 - 12:00
  * **2023-08-01:** 12:00 - 18:00
  * **2023-08-02:** 18:00 - 00:00
  * **2023-08-03:** 00:00 - 06:00
  * **2023-08-04:** 06:00 - 12:00
  * **2023-08-05:** 12:00 - 18:00
  * **2023-08-06:** 18:00 - 00:00
  * **2023-08-07:** 00:00 - 06:00
  * **2023-08-08:** 06:00 - 12:00
