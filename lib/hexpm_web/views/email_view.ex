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
      |> Enum.map(fn([n, c, d]) -> "#{n},#{c},#{d}" end)
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
  end

  defmodule PackagePublished do
    def intro(package, version) do
      """
      You have recently published package #{package} v#{version}.
      If this wasn't done by you, you should reset your account and revert or retire the version.
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
      rebar3 hex retire --pkg #{package} --vsn #{version} --reason security --message "Not published by owners"
      """
    end
  end
end
