defmodule HexpmWeb.EmailView do
  use HexpmWeb, :view

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

    def mix_code() do
      "mix hex.user auth"
    end

    def rebar_code() do
      "rebar3 hex user auth"
    end

    def before_code() do
      "Once this is complete, your existing keys may be invalidated, you will need to regenerate them by running:"
    end

    def after_code() do
      "and entering your username and password."
    end
  end

  defmodule PasswordChanged do
    def greeting(username) do
      "Hello #{username}"
    end

    def title() do
      "Your password on Hex.pm has been changed."
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
      candidates
      |> Enum.map(fn [n, c, d] -> "#{n},#{c},#{d}" end)
      |> Enum.join("\n")
    end
  end

  defmodule OrganizationInvite do
    def access_organization() do
      "You can access organization packages after authenticating in your shell:"
    end

    def mix_code() do
      "mix hex.user auth"
    end

    def rebar_code() do
      "rebar3 hex user auth"
    end
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
