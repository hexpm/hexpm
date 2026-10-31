defmodule HexpmWeb.Components.PublishApprovalNotice do
  use Phoenix.Component

  alias HexpmWeb.ViewHelpers

  attr :packages, :list, required: true

  def publish_approval_notice(assigns) do
    ~H"""
    <section
      :if={@packages != []}
      id="publish-approval-packages"
      class="mb-6 rounded-lg border border-blue-200 dark:border-blue-800 bg-blue-50 dark:bg-blue-950 p-4 sm:p-5 text-sm text-blue-900 dark:text-blue-100"
    >
      <h3 class="font-semibold">Packages that require publish approval</h3>
      <p class="mt-2">
        API keys and workload identities stage releases and documentation for these packages. An existing authorized person must approve each one with fresh 2FA.
      </p>
      <ul class="mt-3 space-y-2 max-h-64 overflow-y-auto">
        <li :for={package <- @packages}>
          <a href={ViewHelpers.path_for_package(package)} class="font-medium underline">{ViewHelpers.package_name(
            package
          )}</a>
          <span class="ml-2 text-xs">{if package.require_publish_approval,
            do: "Package approval enabled",
            else: "Required by organization policy"}</span>
        </li>
      </ul>
    </section>
    """
  end
end
