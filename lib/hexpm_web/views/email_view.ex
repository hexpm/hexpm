defmodule HexpmWeb.EmailView do
  use HexpmWeb, :view

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
