defmodule HexpmWeb.EmailView do
  use HexpmWeb, :view

  def email_uri() do
    Application.fetch_env!(:hexpm, :email_base_url)
    |> URI.new!()
  end

  def email_url(path) do
    Phoenix.VerifiedRoutes.unverified_url(email_uri(), path)
  end

  defmodule Common do
    import Phoenix.HTML, only: [html_escape: 1, safe_to_string: 1]

    @link_style "color: #0f59d8; text-decoration: none;"
    @url_regex ~r{https?://[^\s<>"]+}

    def greeting(username), do: "Hello #{username}"

    def support_email(), do: "support@hex.pm"

    # Smart link wrapping - add <a> only for HTML format
    def link(url, text, :html) do
      safe_to_string(
        PhoenixHTMLHelpers.Link.link(text,
          to: url,
          style: @link_style
        )
      )
    end

    def link(url, _text, :text), do: url

    def support_link(:html), do: link("mailto:#{support_email()}", support_email(), :html)
    def support_link(:text), do: support_email()

    def unauthorized_change_notice(format) do
      "If you did not perform this change, please contact support immediately at #{support_link(format)}."
    end

    def contact_support(format) do
      "If you have any problems don't hesitate to contact support at #{support_link(format)}."
    end

    def questions_notice(format) do
      "If you have any questions about why this action was taken, please contact support at #{support_link(format)}."
    end

    def terms_notice(format) do
      url = HexpmWeb.EmailView.email_url("/policies/termsofservice")

      "This action was taken under our #{link(url, "Terms of Service", format)}. " <>
        "If you have any questions, contact support at #{support_link(format)}."
    end

    def reason_heading(), do: "Reason:"

    def paragraphs(body) do
      body
      |> String.split(~r/\n\s*\n/, trim: true)
      |> Enum.map(&String.trim/1)
      |> Enum.reject(&(&1 == ""))
    end

    # A plain text paragraph rendered for the HTML part: bare URLs become
    # links and single newlines become line breaks. The text is escaped
    # before the markup goes in, so the replacements only ever wrap markup
    # that is already safe, and a URL ending a sentence keeps its punctuation
    # outside the link.
    def html_paragraph(text) do
      text
      |> html_escape()
      |> safe_to_string()
      |> String.replace(@url_regex, &autolink/1)
      |> String.replace("\n", "<br>\n")
    end

    defp autolink(url) do
      {url, trailing} = split_trailing_punctuation(url)
      ~s(<a href="#{url}" style="#{@link_style}">#{url}</a>) <> trailing
    end

    defp split_trailing_punctuation(url) do
      [head, tail] = Regex.run(~r/\A(.*?)([.,;:!?)\]]*)\z/, url, capture: :all_but_first)
      {head, tail}
    end

    # Common labels for build tools
    def for_mix_label(), do: "For mix:"
    def for_rebar3_label(), do: "For rebar3:"
    def for_gleam_label(), do: "For gleam:"

    # URL follow pattern for verification/reset emails
    def follow_link_instruction(url, :html) do
      "You can do so by following #{link(url, "this link", :html)} or by pasting the link below in your web browser."
    end

    def follow_link_instruction(url, :text) do
      "You can do so by following this link:\n\n#{url}"
    end
  end

  defmodule AccountDeletionRequest do
    def title() do
      "Confirm account deletion"
    end

    def message(username) do
      "We received a request to permanently delete the Hex.pm account \"#{username}\". " <>
        "To proceed, open the link below while logged in and confirm the deletion. " <>
        "The link is valid for 24 hours and can only be used once."
    end

    def warning() do
      "If you did not request this, change your password immediately. " <>
        "Changing your password cancels this deletion request."
    end
  end

  defmodule AccountDeleted do
    def title() do
      "Your account has been deleted"
    end

    def message(username) do
      "The Hex.pm account \"#{username}\" has been permanently deleted. " <>
        "The username has been retired and cannot be registered again. " <>
        "Packages and versions you published remain available to the community."
    end
  end

  defmodule AccountRemoved do
    defdelegate reason_heading(), to: Common
    defdelegate terms_notice(format), to: Common
    defdelegate paragraphs(reason), to: Common

    def title() do
      "Your account has been removed"
    end

    def message(username, false) do
      "The Hex.pm account \"#{username}\" has been removed by the Hex.pm team. " <>
        "The username has been retired and cannot be registered again."
    end

    def message(username, true) do
      "The Hex.pm account \"#{username}\" has been removed by the Hex.pm team, " <>
        "along with the packages it was the only owner of. The username has " <>
        "been retired and cannot be registered again."
    end
  end

  defmodule Announcement do
    defdelegate paragraphs(body), to: Common
    defdelegate html_paragraph(text), to: Common

    def title("Hex.pm - " <> title), do: title
    def title(subject), do: subject
  end

  defmodule BuildTools do
    def mix_hex_user_auth(), do: "mix hex.user auth"
    def rebar3_hex_user_auth(), do: "rebar3 hex user auth"
  end

  defmodule OwnerAdd do
    def message(username, package) do
      "#{username} has been added as an owner to package #{package}."
    end
  end

  defmodule OwnerRemove do
    def message(username, package) do
      "#{username} has been removed from owners of package #{package}."
    end
  end

  defmodule Verification do
    def intro() do
      "To begin using your email, we require you to verify your email address."
    end
  end

  defmodule PasswordResetRequest do
    def title() do
      "Reset your Hex.pm password"
    end

    def message() do
      "We heard you've lost your password to Hex.pm. Sorry about that!"
    end

    def new_password_instruction(url, :html) do
      ~s(You can chose a new password by following #{Common.link(url, "this link", :html)} or by pasting the link below in your web browser.)
    end

    def new_password_instruction(_url, :text) do
      "You can chose a new password by following this link"
    end

    defdelegate mix_code(), to: BuildTools, as: :mix_hex_user_auth
    defdelegate rebar_code(), to: BuildTools, as: :rebar3_hex_user_auth

    def before_code() do
      "Once this is complete, your existing keys may be invalidated, you will need to regenerate them by running:"
    end

    def after_code() do
      "and entering your username and password."
    end
  end

  defmodule PasswordChanged do
    defdelegate greeting(username), to: Common

    def title() do
      "Your password on Hex.pm has been changed."
    end

    def password_reset_notice(url, :html) do
      ~s(If you did not perform this change, you can reset your password by entering your email at #{Common.link(url, url, :html)}.)
    end

    def password_reset_notice(url, :text) do
      "If you did not perform this change, you can reset your password by entering your email at #{url}."
    end
  end

  defmodule SecretsDetected do
    def title(), do: "Possible credentials in a published package"

    def intro(package, version, findings) do
      count = length(groups(findings))

      "A scan of #{package} v#{version} found #{credentials(count)} that #{look(count)} like " <>
        "credentials. Anyone who downloads the package can read #{them(count)}."
    end

    defp credentials(1), do: "a value"
    defp credentials(count), do: "#{count} values"

    defp look(1), do: "looks"
    defp look(_count), do: "look"

    defp them(1), do: "it"
    defp them(_count), do: "them"

    def action() do
      "If any of these are real, revoke and reissue them now. The release is public and " <>
        "mirrors have already copied it, so removing the package does not undo the exposure."
    end

    def found_heading(), do: "What was found:"

    # One block per credential, listing every file it was found in. The same
    # value in five files is one thing to revoke, but the owner has to delete
    # all five copies, so naming only the first would send them away half done.
    def groups(findings) do
      findings
      |> Enum.group_by(& &1.fingerprint)
      |> Enum.map(fn {_fingerprint, [first | _] = group} ->
        %{
          rule: first.rule,
          preview: first.preview,
          locations: Enum.map(group, &Hexpm.SecretScan.Finding.location/1)
        }
      end)
      |> Enum.sort_by(& &1.locations)
    end

    def entry(group) do
      Enum.join(["#{group.rule}  #{group.preview}" | group.locations], "\n    ")
    end

    def no_action_taken() do
      "Hex.pm has taken no other action. The package is still published and its owners are " <>
        "unchanged. We store only a hash of each value and the masked preview above, never " <>
        "the value itself."
    end

    def false_positive() do
      "Some of these may be test fixtures or example values, in which case there is nothing " <>
        "to do. You can stop future scans reporting such paths with " <>
        ~s(package: [secret_scan: [ignore: ["test/fixtures/**"]]] in mix.exs.)
    end

    defdelegate questions_notice(format), to: Common
  end

  defmodule SecurityPasswordReset do
    def title() do
      "Your Hex.pm password has been reset"
    end

    def message() do
      "Your password has been reset by Hex.pm administrators for security reasons. " <>
        "This may be due to a security incident, suspicious activity, or a routine security measure."
    end

    def action_instruction(url, :html) do
      ~s(Please set a new password by following #{Common.link(url, "this link", :html)} or by pasting the link below in your web browser.)
    end

    def action_instruction(_url, :text) do
      "Please set a new password by following this link"
    end

    def expired_instruction(reset_url, :html) do
      ~s(If the link above has expired, you can request a new password reset at #{Common.link(reset_url, reset_url, :html)}.)
    end

    def expired_instruction(reset_url, :text) do
      "If the link above has expired, you can request a new password reset at #{reset_url}."
    end

    defdelegate questions_notice(format), to: Common

    defdelegate mix_code(), to: BuildTools, as: :mix_hex_user_auth
    defdelegate rebar_code(), to: BuildTools, as: :rebar3_hex_user_auth

    def before_code() do
      "After resetting your password, you will need to regenerate your API keys by running:"
    end

    def after_code() do
      "and entering your username and new password."
    end
  end

  defmodule TFAEnabled do
    defdelegate greeting(username), to: Common

    def title() do
      "TFA has been enabled on your account."
    end
  end

  defmodule TFAAppEnabled do
    defdelegate greeting(username), to: Common

    def title() do
      "A TFA app has been enabled on your account."
    end
  end

  defmodule TFADisabled do
    defdelegate greeting(username), to: Common

    def title() do
      "TFA has been disabled on your account."
    end
  end

  defmodule TFAAppDisabled do
    defdelegate greeting(username), to: Common

    def title() do
      "A TFA app has been disabled on your account."
    end
  end

  defmodule TFARecoveryCodesRotated do
    defdelegate greeting(username), to: Common

    def title() do
      "TFA recovery codes for your account have been rotated."
    end
  end

  defmodule TyposquatCandidates do
    def intro(threshold) do
      """
      Using Levenshtein Distance with a threshold of #{threshold}
      --------------------
      new_package,current_package,distance
      """
    end

    def table(candidates) do
      Enum.map_join(candidates, "\n", fn [n, c, d] -> "#{n},#{c},#{d}" end)
    end
  end

  defmodule SSOIdentityUnlinked do
    def intro(organization, username, username) do
      "You disconnected your Hex.pm account from the identity provider of the #{organization} organization."
    end

    def intro(organization, _username, unlinked_by) do
      "#{unlinked_by}, an administrator of the #{organization} organization, disconnected your Hex.pm account from the organization's identity provider."
    end

    def access(true) do
      "The organization requires single sign-on for your account, and disconnecting ended your current sign-ins to it, so you can't reach it until you connect your account again by signing in through the provider:"
    end

    def access(false) do
      "The organization doesn't require single sign-on for your account at the moment, so your access to it hasn't changed. You can connect your account again by signing in through the provider:"
    end

    def questions(_organization, username, username), do: nil

    def questions(organization, _username, _unlinked_by) do
      "If you don't know why this happened, ask an administrator of the #{organization} organization."
    end
  end

  defmodule SSOSeats do
    def heading("seats_exhausted"), do: "Organization Has No Seats Left"
    def heading("expansion_failed"), do: "A Seat Could Not Be Added"
    def heading("seat_limit_unknown"), do: "Seat Count Could Not Be Read"

    def body(kind, source, organization) do
      "#{attempt(source, organization)}, but #{problem(kind)}. #{outcome(source)}"
    end

    defp attempt("login", organization) do
      "Someone signed in to the #{organization} organization through your identity provider and would have been added as a member"
    end

    defp attempt("scim", organization) do
      "Your identity provider asked through SCIM provisioning for someone to be added to the #{organization} organization"
    end

    defp problem("seats_exhausted"), do: "there were no seats left"
    defp problem("expansion_failed"), do: "buying the extra seat failed"

    defp problem("seat_limit_unknown"),
      do: "Hex.pm couldn't read how many seats the organization has paid for"

    defp outcome("login"), do: "They were turned away and nothing was billed."
    defp outcome("scim"), do: "They weren't added and nothing was billed."

    def next_step("seats_exhausted", "login") do
      "Add seats from the organization billing page and ask them to sign in again."
    end

    def next_step("seats_exhausted", "scim") do
      "Add seats from the organization billing page. They're added the next time your identity provider sends the request."
    end

    def next_step("expansion_failed", _source) do
      "Check the payment method on the organization billing page. For an hour after a failed purchase, anyone who needs a new seat is turned away without another purchase attempt. The first attempt after that tries the purchase again."
    end

    def next_step("seat_limit_unknown", _source) do
      "Hex.pm reads the seat count from the billing service every minute, so this usually clears up on its own. If it keeps happening, contact support at #{Common.support_email()}."
    end

    def rate_limit() do
      "Further attempts are recorded on the SSO settings page, but a seat notice like this one is only sent once an hour."
    end
  end

  defmodule SSOEnforcement do
    def scope() do
      "That covers the organization's private packages and dashboard, and publishing or managing public packages you can only manage because the organization owns them."
    end

    def account_notice() do
      "Signing in to Hex.pm itself doesn't change, and neither does your access to other organizations or to packages you own yourself."
    end

    def mix_notice() do
      "That includes mix, which asks you to authenticate in a browser when it needs a package from the organization."
    end

    def duration(3_600), do: "hour"

    def duration(seconds) when rem(seconds, 86_400) == 0 and seconds > 86_400,
      do: "#{div(seconds, 86_400)} days"

    def duration(seconds) when rem(seconds, 3_600) == 0, do: "#{div(seconds, 3_600)} hours"
    def duration(seconds), do: "#{div(seconds, 60)} minutes"
  end

  defmodule SSOEnforcementPending do
    defdelegate scope(), to: SSOEnforcement
    defdelegate account_notice(), to: SSOEnforcement

    def session(session_lifetime) do
      "Once it applies, you sign in through the provider when you reach the organization, and again every #{SSOEnforcement.duration(session_lifetime)}. #{SSOEnforcement.mix_notice()}"
    end

    def intro(organization, required_at) do
      "From #{Calendar.strftime(required_at, "%B %-d, %Y")}, reaching the #{organization} organization on Hex.pm will require signing in through its identity provider."
    end

    def linked(true), do: "Your Hex.pm account is already connected to that provider."

    def linked(false) do
      "Your Hex.pm account isn't connected to that provider yet. Connect it before then by signing in through the provider, or you'll lose that access on that date until you do:"
    end

    def keys(%{revoked: [], trimmed: [], blocked: []}), do: []

    def keys(keys) do
      [
        "The organization doesn't accept personal API keys from the members it requires single sign-on for, so on that date:"
        | Enum.reject(
            [
              revoked(keys.revoked),
              trimmed(keys.trimmed),
              blocked(keys.blocked),
              "For continuous integration, use an organization key, which authenticates as the organization rather than as a person and is unaffected."
            ],
            &is_nil/1
          )
      ]
    end

    defp revoked([]), do: nil

    defp revoked([key_name]),
      do:
        "Your key #{key_name} carries nothing but access to this organization, so it will be revoked."

    defp revoked(key_names),
      do:
        "Your keys #{Enum.join(key_names, ", ")} carry nothing but access to this organization, so they will be revoked."

    defp trimmed([]), do: nil

    defp trimmed([key_name]),
      do:
        "Your key #{key_name} will lose its permissions for this organization and keep the rest."

    defp trimmed(key_names),
      do:
        "Your keys #{Enum.join(key_names, ", ")} will lose their permissions for this organization and keep the rest."

    defp blocked([]), do: nil

    defp blocked([key_name]),
      do:
        "Your key #{key_name} reaches this organization through wider permissions, which it keeps, but the organization will refuse it."

    defp blocked(key_names),
      do:
        "Your keys #{Enum.join(key_names, ", ")} reach this organization through wider permissions, which they keep, but the organization will refuse them."
  end

  defmodule SSOEnforcementStarted do
    defdelegate scope(), to: SSOEnforcement
    defdelegate account_notice(), to: SSOEnforcement

    def intro(organization) do
      "Reaching the #{organization} organization on Hex.pm now requires you to sign in through its identity provider."
    end

    def not_linked() do
      "Your Hex.pm account isn't connected to that provider, so you can't reach any of that until you connect it by signing in through the provider:"
    end

    def session(session_lifetime) do
      "After that, you sign in through the provider again every #{SSOEnforcement.duration(session_lifetime)}. #{SSOEnforcement.mix_notice()}"
    end
  end

  defmodule SSOKeysRefused do
    def removed(organization, revoked, trimmed) do
      "The #{organization} organization on Hex.pm now requires single sign-on, and chose not to allow personal API keys. #{keys_removed(revoked ++ trimmed)} to that organization removed."
    end

    # A key whose only permission named this organization has nothing left to
    # authorize, so it is revoked rather than left inert.
    def rest_of_key([], trimmed), do: kept(trimmed)

    def rest_of_key(revoked, []) do
      "#{subject(revoked)} nothing else, so #{pronoun(revoked)} been revoked."
    end

    def rest_of_key(revoked, trimmed) do
      "#{subject(revoked)} nothing else, so #{pronoun(revoked)} been revoked. #{kept(trimmed)}"
    end

    def refused(organization, blocked, []) do
      "The #{organization} organization on Hex.pm authenticates its members through an identity provider, and chose not to accept personal API keys from the members it covers. Your account is one of them, so #{keys_refused(blocked)} that organization."
    end

    def refused(organization, blocked, _changed) do
      "The #{organization} organization does not accept personal API keys from the members it covers at all, so #{keys_refused(blocked)} it either."
    end

    def unchanged([_key_name]) do
      "That key itself is untouched. It still exists, still carries the permissions it always did, and still works for everything else it reaches. Only the requests it makes to this organization are refused."
    end

    def unchanged(_key_names) do
      "Those keys themselves are untouched. They still exist, still carry the permissions they always did, and still work for everything else they reach. Only the requests they make to this organization are refused."
    end

    def alternatives() do
      "For your own work, run mix hex.user auth and sign in, which authenticates you through the provider when the organization asks for it. For continuous integration, use an organization key, which authenticates as the organization rather than as a person and is unaffected."
    end

    # mix hex.organization auth stores a key per organization, and mix uses a
    # stored key ahead of the account sign-in. mix hex.user auth leaves those
    # stored keys in place.
    def stored_key(organization) do
      "If you ran mix hex.organization auth #{organization} on a machine, mix stored a key for the organization there and keeps using it instead of your sign-in. Run mix hex.organization deauth #{organization} on that machine to remove it."
    end

    def why() do
      "A personal key is a static credential. There is nothing for the organization's provider to check when it is used, and nothing that expires it, which is why an organization requiring SSO can choose to turn them away."
    end

    defp kept([key_name]),
      do:
        "The key #{key_name} still works for everything else it could reach. Only the permissions naming this organization were removed."

    defp kept(key_names) do
      "The keys #{Enum.join(key_names, ", ")} still work for everything else they could reach. Only the permissions naming this organization were removed."
    end

    defp subject([key_name]), do: "The key #{key_name} carried"
    defp subject(key_names), do: "The keys #{Enum.join(key_names, ", ")} carried"

    defp pronoun([_key_name]), do: "it has"
    defp pronoun(_key_names), do: "they have"

    defp keys_removed([key_name]), do: "Your key #{key_name} has had its access"

    defp keys_removed(key_names) do
      "Your keys #{Enum.join(key_names, ", ")} have had their access"
    end

    defp keys_refused([key_name]), do: "your key #{key_name} no longer reaches"

    defp keys_refused(key_names) do
      "your keys #{Enum.join(key_names, ", ")} no longer reach"
    end
  end

  defmodule SSOBreakGlass do
    def intro(organization, username, screen) do
      case purpose(screen) do
        nil ->
          "#{username} reached the #{organization} organization on Hex.pm without a current single sign-on session."

        purpose ->
          "#{username} reached the #{organization} organization on Hex.pm without a current single sign-on session, to #{purpose}."
      end
    end

    # The screens enforcement leaves open, named by the controller action that
    # served them.
    defp purpose("billing"), do: "open the billing page"
    defp purpose("billing_token"), do: "add a payment method"
    defp purpose("create_billing"), do: "set up billing"
    defp purpose("update_billing"), do: "change the billing details"
    defp purpose("cancel_billing"), do: "cancel the subscription"
    defp purpose("resume_billing"), do: "resume the subscription"
    defp purpose("change_plan"), do: "change the plan"
    defp purpose("add_seats"), do: "add seats"
    defp purpose("remove_seats"), do: "remove seats"
    defp purpose("show_invoice"), do: "view an invoice"
    defp purpose("pay_invoice"), do: "pay an invoice"
    defp purpose("void_invoice"), do: "void an invoice"
    defp purpose("sso"), do: "open the SSO settings"
    defp purpose("configure"), do: "change the identity provider settings"
    defp purpose("test"), do: "test the identity provider connection"
    defp purpose("enable"), do: "turn on login through the identity provider"
    defp purpose("disable"), do: "turn off login through the identity provider"
    defp purpose("delete"), do: "delete the identity provider connection"
    defp purpose("rotate"), do: "start replacing the identity provider client secret"
    defp purpose("promote"), do: "switch to the new identity provider client secret"
    defp purpose("unlink"), do: "disconnect a member's account from the identity provider"
    defp purpose("configure_jit"), do: "change just-in-time membership"
    defp purpose("configure_enforcement"), do: "change SSO enforcement"
    defp purpose("delete_scim_token"), do: "turn off SCIM provisioning"
    defp purpose("add_domain"), do: "add a domain"
    defp purpose("verify_domain"), do: "verify a domain"
    defp purpose("remove_domain"), do: "remove a domain"
    defp purpose(_screen), do: nil

    def why() do
      "An organization whose provider stops working, or whose administrator is deactivated in it by mistake, still has to be able to repair the connection, keep paying, and leave. It couldn't do any of that if those screens sat behind the gate they're the only way to unlock."
    end

    def scope() do
      "Private packages, publishing and the rest of the organization dashboard were refused as usual. Billing and the SSO settings stay open to administrators and aren't read-only: billing can be changed and the subscription cancelled, and the SSO settings can replace the provider, unlink accounts and turn enforcement off. The SSO settings also show the linked accounts, the personal API keys that reach this organization, and recent login failures."
    end

    def action(username) do
      "This notice is sent at most once an hour for each member. The audit log records everything reached this way, including anything this notice doesn't name. If you didn't expect #{username} to do this, review the organization's administrators and audit log."
    end
  end

  defmodule OrganizationInvitation do
    def intro(organization, role) do
      "You have been invited to join the #{organization} organization on Hex.pm as #{article(role)} #{role} member."
    end

    def sign_in_notice() do
      "Accepting adds the Hex account you are signed in as to the organization. If you do not have one yet you can create it first, then follow the link again."
    end

    def expiry(expires_at) do
      "This invitation expires on #{Calendar.strftime(expires_at, "%B %-d, %Y")}."
    end

    def ignore_notice() do
      "If you were not expecting this invitation you can ignore this email and nothing will happen."
    end

    defp article("admin"), do: "an"
    defp article(_role), do: "a"
  end

  defmodule OrganizationInvite do
    def access_organization() do
      "You can access organization packages after authenticating in your shell:"
    end

    def check_out_org(org_url, username, :html) do
      ~s(Go check out the #{Common.link(org_url, "organization", :html)}, if you do not want to join the organization you can leave it from the dashboard. You need to be logged in as <strong>#{username}</strong> to access it.)
    end

    def check_out_org(org_url, username, :text) do
      "Go check out the organization[0], if you do not want to join the organization you can leave it from the dashboard. You need to be logged in as #{username} to access it.\n\n[0] #{org_url}"
    end

    def docs_link(docs_url, :html) do
      ~s(To learn more about private packages and organizations go to the #{Common.link(docs_url, "documentation", :html)}.)
    end

    def docs_link(docs_url, :text) do
      "To learn more about private packages and organizations go to the documentation[1].\n\n[1] #{docs_url}"
    end

    defdelegate mix_code(), to: BuildTools, as: :mix_hex_user_auth
    defdelegate rebar_code(), to: BuildTools, as: :rebar3_hex_user_auth
  end

  defmodule PackagePublished do
    def intro(nil, package, version) do
      """
      Package #{package} v#{version} was recently published.
      If this wasn't done by you or one of the other package owners, you should
      reset your account and revert or retire the version.
      """
    end

    def intro(publisher, package, version) do
      """
      Package #{package} v#{version} was recently published by #{publisher.username}.
      If this wasn't done by you or one of the other package owners, you should
      reset your account and revert or retire the version.
      """
    end

    def mix_code(package, version) do
      """
      cd #{package}; mix hex.publish --revert #{version}
      # or
      mix hex.retire #{package} #{version} security --message "Not published by owners"
      """
    end

    def rebar3_code(package, version) do
      """
      cd #{package}; rebar3 hex publish --revert #{version}
      # or
      rebar3 hex retire #{package} #{version} security --message "Not published by owners"
      """
    end

    def gleam_code(package, version) do
      """
      gleam hex revert --package #{package} --version #{version}
      # or
      gleam hex retire --package #{package} --version #{version} security --message "Not published by owners"
      """
    end
  end

  defmodule PackageRemoved do
    defdelegate reason_heading(), to: Common
    defdelegate terms_notice(format), to: Common
    defdelegate paragraphs(reason), to: Common

    def title(package) do
      "Package #{package} has been removed"
    end

    def message(package) do
      "The package #{package} and all of its releases have been removed from Hex.pm " <>
        "by the Hex.pm team."
    end
  end

  defmodule ReleaseRemoved do
    defdelegate reason_heading(), to: Common
    defdelegate terms_notice(format), to: Common
    defdelegate paragraphs(reason), to: Common

    def title(package, version) do
      "#{package} v#{version} has been removed"
    end

    def message(package, version, 0) do
      "Version #{version} of the package #{package} has been removed from Hex.pm " <>
        "by the Hex.pm team. It was the only version, so the package no longer " <>
        "has any releases."
    end

    def message(package, version, _remaining) do
      "Version #{version} of the package #{package} has been removed from Hex.pm " <>
        "by the Hex.pm team. Other versions of the package are unaffected."
    end
  end
end
