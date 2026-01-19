defmodule HexpmWeb.EmailView do
  use HexpmWeb, :view

  defmodule Common do
    import Phoenix.HTML, only: [safe_to_string: 1]

    def greeting(username), do: "Hello #{username}"

    def support_email(), do: "support@hex.pm"

    # Smart link wrapping - add <a> only for HTML format
    def link(url, text, :html), do: safe_to_string(PhoenixHTMLHelpers.Link.link(text, to: url))
    def link(url, _text, :text), do: url

    def support_link(:html), do: link("mailto:#{support_email()}", support_email(), :html)
    def support_link(:text), do: support_email()

    def unauthorized_change_notice(format) do
      "If you did not perform this change, please contact support immediately at #{support_link(format)}."
    end

    def contact_support(format) do
      "If you have any problems don't hesitate to contact support at #{support_link(format)}."
    end

    # Common labels for build tools
    def for_mix_label(), do: "For mix:"
    def for_rebar3_label(), do: "For rebar3:"

    # URL follow pattern for verification/reset emails
    def follow_link_instruction(url, :html) do
      "You can do so by following #{link(url, "this link", :html)} or by pasting this link in your web browser: #{url}"
    end

    def follow_link_instruction(url, :text) do
      "You can do so by following this link:\n\n#{url}"
    end
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
