defmodule HexpmWeb.Components.Flash do
  @moduledoc """
  Flash message component with auto-dismiss using Phoenix.LiveView.JS.
  """
  use Phoenix.Component
  alias Phoenix.LiveView.JS
  import HexpmWeb.ViewIcons, only: [icon: 3]

  @doc """
  Renders a flash message with auto-dismiss after 7 seconds.
  """
  attr :id, :string, required: true
  attr :type, :atom, required: true, values: [:error, :success, :info, :warning]
  attr :message, :any, required: true
  attr :class, :string, default: ""

  def flash_message(assigns) do
    ~H"""
    <div
      id={@id}
      class={[
        "tw:flex tw:items-center tw:gap-3 tw:px-4 tw:py-3 tw:rounded-lg tw:border tw:shadow-lg",
        "tw:animate-[flash-autodismiss_7s_ease-in-out_forwards]",
        flash_bg_color(@type),
        flash_border_color(@type),
        "flash-message",
        @class
      ]}
      role="alert"
    >
      <%!-- Icon --%>
      <div class="tw:shrink-0 tw:mt-[2px]">
        {flash_icon(@type)}
      </div>

      <%!-- Message --%>
      <div class={["tw:flex-1 tw:text-small tw:leading-5", flash_text_color(@type)]}>
        {@message}
      </div>

      <%!-- Close Button --%>
      <button
        type="button"
        class={[
          "tw:shrink-0 tw:-mr-1 tw:mt-[2px] tw:p-1 tw:rounded tw:transition-colors",
          flash_close_hover_color(@type)
        ]}
        phx-click={dismiss_flash(@id)}
        aria-label="Dismiss"
      >
        {icon(:heroicon, "x-mark", width: 16, height: 16)}
      </button>
    </div>
    """
  end

  # Manual dismiss using LiveView JS (works on all pages via phx-click)
  defp dismiss_flash(id) do
    JS.hide(
      to: "##{id}",
      transition:
        {"tw:transition-opacity tw:ease-out tw:duration-300", "tw:opacity-100", "tw:opacity-0"}
    )
  end

  # Background colors for each flash type
  defp flash_bg_color(:error), do: "tw:bg-red-100"
  defp flash_bg_color(:success), do: "tw:bg-green-100"
  defp flash_bg_color(:info), do: "tw:bg-blue-100"
  defp flash_bg_color(:warning), do: "tw:bg-yellow-100"

  # Border colors for each flash type
  defp flash_border_color(:error), do: "tw:border-red-300"
  defp flash_border_color(:success), do: "tw:border-green-300"
  defp flash_border_color(:info), do: "tw:border-blue-300"
  defp flash_border_color(:warning), do: "tw:border-yellow-300"

  # Text colors for each flash type
  defp flash_text_color(:error), do: "tw:text-red-800"
  defp flash_text_color(:success), do: "tw:text-green-800"
  defp flash_text_color(:info), do: "tw:text-blue-800"
  defp flash_text_color(:warning), do: "tw:text-yellow-900"

  # Close button hover colors
  defp flash_close_hover_color(:error), do: "tw:hover:bg-red-200"
  defp flash_close_hover_color(:success), do: "tw:hover:bg-green-200"
  defp flash_close_hover_color(:info), do: "tw:hover:bg-blue-200"
  defp flash_close_hover_color(:warning), do: "tw:hover:bg-yellow-200"

  # Icons for each flash type
  defp flash_icon(:error) do
    icon(:heroicon, "x-circle", width: 20, height: 20, class: "tw:text-red-600")
  end

  defp flash_icon(:success) do
    icon(:heroicon, "check-circle", width: 20, height: 20, class: "tw:text-green-600")
  end

  defp flash_icon(:info) do
    icon(:heroicon, "information-circle", width: 20, height: 20, class: "tw:text-blue-600")
  end

  defp flash_icon(:warning) do
    icon(:heroicon, "exclamation-triangle", width: 20, height: 20, class: "tw:text-yellow-600")
  end
end
