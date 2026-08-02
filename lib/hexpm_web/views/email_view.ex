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
    import Phoenix.HTML, only: [safe_to_string: 1]

    def greeting(username), do: "Hello #{username}"

    def support_email(), do: "support@hex.pm"

    # Smart link wrapping - add <a> only for HTML format
    def link(url, text, :html) do
      safe_to_string(
        PhoenixHTMLHelpers.Link.link(text,
          to: url,
          style: "color: #0f59d8; text-decoration: none;"
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

    def reason_heading(), do: "Reason:"

    def paragraphs(body) do
      body
      |> String.split(~r/\n\s*\n/, trim: true)
      |> Enum.map(&String.trim/1)
      |> Enum.reject(&(&1 == ""))
    end

    # Common labels for build tools
    def for_mix_label(), do: "For mix:"
    def for_rebar3_label(), do: "For rebar3:"
    def for_gleam_label(), do: "For gleam:"

    # URL follow pattern for verification/reset emails
    def follow_link_instruction(url, :html) do
      "You can do so by following #{link(url, "this link", :html)} or by pasting this link in your web browser: #{url}"
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
    defdelegate questions_notice(format), to: Common
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

  defmodule SSOSeats do
    def heading("seats_exhausted"), do: "Organization Has No Seats Left"
    def heading("expansion_failed"), do: "A Seat Could Not Be Added"

    def body("seats_exhausted", organization) do
      "Someone authenticated to the #{organization} organization through your identity provider and would have been added as a member, but there were no seats left. They were turned away and nothing was billed."
    end

    def body("expansion_failed", organization) do
      "Someone authenticated to the #{organization} organization through your identity provider and would have been added as a member, but the seat could not be purchased. They were turned away and nothing was billed."
    end

    def next_step("seats_exhausted") do
      "Add seats from the organization billing page and ask them to sign in again. Further attempts are recorded on the SSO settings page, but this notice is only sent once an hour."
    end

    def next_step("expansion_failed") do
      "Check the payment method on the organization billing page. Until it works, further logins are turned away without retrying the purchase."
    end
  end

  defmodule SSOEnforcementPending do
    def intro(organization, required_at) do
      "From #{Calendar.strftime(required_at, "%B %-d, %Y")}, reaching the #{organization} organization on Hex.pm will require signing in through its identity provider."
    end

    def not_linked() do
      "Your Hex account is not connected to that provider yet. Connect it before then and nothing about your day changes. Leave it until after and you lose access to the organization's private packages until you do."
    end

    def account_notice() do
      "This does not affect your Hex account itself, your own packages, or any other organization you belong to. You keep signing in to Hex.pm exactly as you do now."
    end

    def cli_notice() do
      "Command line access is included. Once enforcement starts, mix will ask you to authenticate in a browser the first time it needs a package from this organization, and again whenever the organization's authentication window lapses."
    end
  end

  defmodule SSOKeyRevoked do
    def intro(organization, key_names) do
      "The #{organization} organization on Hex.pm now requires single sign-on, and chose not to allow personal API keys. #{keys(key_names)} had its access to that organization removed."
    end

    def rest_of_key([_key_name]) do
      "The key still works for everything else it could reach. Only the permissions naming this organization were removed."
    end

    def rest_of_key(_key_names) do
      "The keys still work for everything else they could reach. Only the permissions naming this organization were removed."
    end

    defp keys([key_name]), do: "Your key #{key_name} has"

    defp keys(key_names) do
      "Your keys #{Enum.join(key_names, ", ")} have"
    end

    def alternatives() do
      "For your own work, run mix hex.user auth and sign in, which authenticates you through the provider when the organization asks for it. For continuous integration, use an organization key, which authenticates as the organization rather than as a person and is unaffected."
    end

    def why() do
      "A personal key is a static credential. There is nothing for the organization's provider to check when it is used, and nothing that expires it, which is why an organization requiring SSO can choose to turn them away."
    end
  end

  defmodule SSOBreakGlass do
    def intro(organization, username) do
      "#{username} opened the billing or single sign-on settings for the #{organization} organization on Hex.pm without a current single sign-on session."
    end

    def why() do
      "Those two screens are the only ones enforcement leaves open. An organization whose provider stops working, or whose administrator is deactivated in it by mistake, still has to be able to repair the connection and keep paying, and it could not if those screens sat behind the same gate."
    end

    def scope() do
      "Nothing else was reachable. Private packages, members, keys and every other organization page were refused as usual."
    end

    def action() do
      "If this was not one of your administrators, review the organization's members and audit log."
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
    defdelegate questions_notice(format), to: Common
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
    defdelegate questions_notice(format), to: Common
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

  defmodule ReportState do
    def state_explain("to_accept") do
      """
      The report has now state \"to_accept\".
      This means that the vulnerability reported has to be reviewed by a moderator in order to be recognized or not as a real vulnerability.
      Only the report author and moderators can see the report description.
      """
    end

    def state_explain("accepted") do
      """
      The report has now state \"accepted\".
      This means that the vulnerability reported has been recognized by a moderator as real.
      A comments section has been enabled on the report for moderators, owners and the report author to discuss the vulnerability.
      """
    end

    def state_explain("solved") do
      """
      The report has now state \"solved\".
      This means that the vulnerability reported has been solved.
      Now the report is public, so users other than the report author, moderators and the reported package owners can read the report description.
      """
    end

    def state_explain("rejected") do
      """
      The report has now state \"rejected\".
      This means that the vulnerability reported has not been recognized as such a vulnerability by a moderator.
      The report will not be made public, so users other than the report author and moderators will not be able to read the report description or the comments section.
      Moderators and the report author can still comment about the report on the report's comment section.
      """
    end

    def state_explain("unresolved") do
      """
      The report has now state \"unresolved\".
      This means the report has been on a revision state (\"accepted\") for too long.
      Now the report is public, so users other than the report author, moderators and the reported package owners can read the report description.
      """
    end
  end
end
