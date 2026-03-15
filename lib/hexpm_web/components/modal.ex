defmodule HexpmWeb.Components.Modal do
  @moduledoc """
  Reusable modal component with backdrop and close functionality.

  ## Examples

      <.modal id="confirm-modal" title="Confirm Action">
        <p>Are you sure you want to proceed?</p>
        <:footer>
          <.button type="button" variant="secondary" phx-click={JS.exec("data-cancel", to: "#confirm-modal")}>
            Cancel
          </.button>
          <.button type="submit" variant="primary">
            Confirm
          </.button>
        </:footer>
      </.modal>

      # Show modal with Phoenix.LiveView.JS:
      <.button phx-click={show_modal("my-modal")}>Open</.button>
  """
  use Phoenix.Component
  import HexpmWeb.Components.Buttons, only: [icon_button: 1]
  alias Phoenix.LiveView.JS

  @doc """
  Shows a modal by ID using Phoenix.LiveView.JS commands.
  Can be used in phx-click attributes.

  ## Examples
      <.button phx-click={show_modal("my-modal")}>Open Modal</.button>
  """
  def show_modal(js \\ %JS{}, id) when is_binary(id) do
    js
    |> JS.remove_class("hidden",
      to: "##{id}",
      transition: {"transition-all transform ease-out duration-300", "opacity-0", "opacity-100"}
    )
    |> JS.remove_class("hidden",
      to: "##{id}-backdrop",
      transition: {"transition-all transform ease-out duration-300", "opacity-0", "opacity-100"}
    )
    |> JS.remove_class("hidden",
      to: "##{id}-content",
      transition:
        {"transition-all transform ease-out duration-300",
         "opacity-0 translate-y-4 sm:translate-y-0 sm:scale-95",
         "opacity-100 translate-y-0 sm:scale-100"}
    )
    |> JS.add_class("overflow-hidden", to: "body")
    |> JS.focus_first(to: "##{id}-content")
  end

  @doc """
  Hides a modal by ID using Phoenix.LiveView.JS commands.

  ## Examples
      <.button phx-click={hide_modal("my-modal")}>Close Modal</.button>
  """
  def hide_modal(js \\ %JS{}, id) do
    js
    |> JS.add_class("hidden",
      to: "##{id}",
      transition: {"transition-all transform ease-in duration-200", "opacity-100", "opacity-0"}
    )
    |> JS.add_class("hidden",
      to: "##{id}-backdrop",
      transition: {"transition-all transform ease-in duration-200", "opacity-100", "opacity-0"}
    )
    |> JS.add_class("hidden",
      to: "##{id}-content",
      transition:
        {"transition-all transform ease-in duration-200",
         "opacity-100 translate-y-0 sm:scale-100",
         "opacity-0 translate-y-4 sm:translate-y-0 sm:scale-95"}
    )
    |> JS.remove_class("overflow-hidden", to: "body")
  end

  @doc """
  Renders a modal dialog.
  """
  attr :id, :string, required: true
  attr :title, :string, default: nil
  attr :show, :boolean, default: false
  attr :max_width, :string, default: "2xl", values: ["sm", "md", "lg", "xl", "2xl", "3xl", "4xl"]
  attr :class, :string, default: ""

  slot :inner_block, required: true
  slot :header, doc: "Optional custom header content (overrides title)"
  slot :footer, doc: "Optional footer content with actions"

  def modal(assigns) do
    ~H"""
    <div
      id={@id}
      class={["relative z-50", unless(@show, do: "hidden"), @class]}
      aria-labelledby={"#{@id}-title"}
    >
      <%!-- Backdrop --%>
      <div
        id={"#{@id}-backdrop"}
        class={["fixed inset-0 bg-grey-900/25 transition-opacity", unless(@show, do: "hidden")]}
        aria-hidden="true"
        phx-click={hide_modal(@id)}
      >
      </div>

      <%!-- Modal Container --%>
      <div class="fixed inset-0 z-10 overflow-y-auto">
        <div class="flex min-h-full items-center justify-center p-4">
          <%!-- Modal Content --%>
          <div
            id={"#{@id}-content"}
            class={[
              "relative w-full bg-white rounded-[20px] flex flex-col max-h-[calc(100vh-2rem)] p-6",
              "shadow-[0px_15px_50px_0px_rgba(3,9,19,0.4)]",
              unless(@show, do: "hidden"),
              modal_max_width(@max_width)
            ]}
            role="dialog"
            aria-modal="true"
            phx-click-away={hide_modal(@id)}
            phx-window-keydown={hide_modal(@id)}
            phx-key="escape"
          >
            <%!-- Close Button (top right) --%>
            <div class="absolute top-6 right-6">
              <.icon_button
                icon="x-mark"
                variant="default"
                phx-click={hide_modal(@id)}
                aria-label="Close modal"
              />
            </div>

            <%!-- Header --%>
            <%= if @header != [] || @title do %>
              <div class="mb-4 pr-10">
                <%= if @header != [] do %>
                  {render_slot(@header)}
                <% else %>
                  <h2 id={"#{@id}-title"} class="text-lg font-semibold text-grey-900">
                    {@title}
                  </h2>
                <% end %>
              </div>
            <% end %>

            <%!-- Body --%>
            <div class="flex-1 overflow-y-auto px-0.5 py-0.5">
              {render_slot(@inner_block)}
            </div>

            <%!-- Footer --%>
            <%= if @footer != [] do %>
              <div class="flex items-center justify-end gap-3 mt-6">
                {render_slot(@footer)}
              </div>
            <% end %>
          </div>
        </div>
      </div>
    </div>
    """
  end

  defp modal_max_width("sm"), do: "max-w-sm"
  defp modal_max_width("md"), do: "max-w-md"
  defp modal_max_width("lg"), do: "max-w-lg"
  defp modal_max_width("xl"), do: "max-w-xl"
  defp modal_max_width("2xl"), do: "max-w-2xl"
  defp modal_max_width("3xl"), do: "max-w-3xl"
  defp modal_max_width("4xl"), do: "max-w-4xl"
end
