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
        "flex items-center gap-3 px-4 py-3 rounded-lg border shadow-lg",
        "animate-[flash-autodismiss_7s_ease-in-out_forwards]",
        flash_bg_color(@type),
        flash_border_color(@type),
        "flash-message",
        @class
      ]}
      role="alert"
    >
      <%!-- Icon --%>
      <div class="shrink-0 mt-[2px]">
        {flash_icon(@type)}
      </div>

      <%!-- Message --%>
      <div class={["flex-1 text-small leading-5", flash_text_color(@type)]}>
        {@message}
      </div>

      <%!-- Close Button --%>
      <button
        type="button"
        class={[
          "shrink-0 -mr-1 mt-[2px] p-1 rounded transition-colors",
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
      transition: {"transition-opacity ease-out duration-300", "opacity-100", "opacity-0"}
    )
  end

  # Background colors for each flash type
  defp flash_bg_color(:error), do: "bg-red-100 dark:bg-red-900/30"
  defp flash_bg_color(:success), do: "bg-green-100 dark:bg-green-900/30"
  defp flash_bg_color(:info), do: "bg-blue-100 dark:bg-blue-900/30"
  defp flash_bg_color(:warning), do: "bg-yellow-100 dark:bg-yellow-900/30"

  # Border colors for each flash type
  defp flash_border_color(:error), do: "border-red-300 dark:border-red-800"
  defp flash_border_color(:success), do: "border-green-300 dark:border-green-800"
  defp flash_border_color(:info), do: "border-blue-300 dark:border-blue-800"
  defp flash_border_color(:warning), do: "border-yellow-300 dark:border-yellow-800"

  # Text colors for each flash type
  defp flash_text_color(:error), do: "text-red-800 dark:text-red-100"
  defp flash_text_color(:success), do: "text-green-800 dark:text-green-100"
  defp flash_text_color(:info), do: "text-blue-800 dark:text-blue-100"
  defp flash_text_color(:warning), do: "text-yellow-900 dark:text-yellow-100"

  # Close button hover colors
  defp flash_close_hover_color(:error), do: "hover:bg-red-200 dark:hover:bg-red-800/50"
  defp flash_close_hover_color(:success), do: "hover:bg-green-200 dark:hover:bg-green-800/50"
  defp flash_close_hover_color(:info), do: "hover:bg-blue-200 dark:hover:bg-blue-800/50"
  defp flash_close_hover_color(:warning), do: "hover:bg-yellow-200 dark:hover:bg-yellow-800/50"

  # Icons for each flash type
  defp flash_icon(:error) do
    icon(:heroicon, "x-circle", width: 20, height: 20, class: "text-red-600 dark:text-red-300")
  end

  defp flash_icon(:success) do
    icon(:heroicon, "check-circle",
      width: 20,
      height: 20,
      class: "text-green-600 dark:text-green-300"
    )
  end

  defp flash_icon(:info) do
    icon(:heroicon, "information-circle",
      width: 20,
      height: 20,
      class: "text-blue-600 dark:text-blue-300"
    )
  end

  defp flash_icon(:warning) do
    icon(:heroicon, "exclamation-triangle",
      width: 20,
      height: 20,
      class: "text-yellow-600 dark:text-yellow-300"
    )
  end
end
