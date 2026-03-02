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

      # Show modal with onclick:
      <button onclick="document.getElementById('my-modal').showModal()">Open</button>

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
    |> JS.show(
      to: "##{id}",
      transition:
        {"tw:transition-all tw:transform tw:ease-out tw:duration-300", "tw:opacity-0",
         "tw:opacity-100"}
    )
    |> JS.show(
      to: "##{id}-backdrop",
      transition:
        {"tw:transition-all tw:transform tw:ease-out tw:duration-300", "tw:opacity-0",
         "tw:opacity-100"}
    )
    |> JS.show(
      to: "##{id}-content",
      transition:
        {"tw:transition-all tw:transform tw:ease-out tw:duration-300",
         "tw:opacity-0 tw:translate-y-4 sm:tw:translate-y-0 sm:tw:scale-95",
         "tw:opacity-100 tw:translate-y-0 sm:tw:scale-100"}
    )
    |> JS.add_class("tw:overflow-hidden", to: "body")
    |> JS.focus_first(to: "##{id}-content")
  end

  @doc """
  Hides a modal by ID using Phoenix.LiveView.JS commands.

  ## Examples
      <.button phx-click={hide_modal("my-modal")}>Close Modal</.button>
  """
  def hide_modal(js \\ %JS{}, id) do
    js
    |> JS.hide(
      to: "##{id}",
      transition:
        {"tw:transition-all tw:transform tw:ease-in tw:duration-200", "tw:opacity-100",
         "tw:opacity-0"}
    )
    |> JS.hide(
      to: "##{id}-backdrop",
      transition:
        {"tw:transition-all tw:transform tw:ease-in tw:duration-200", "tw:opacity-100",
         "tw:opacity-0"}
    )
    |> JS.hide(
      to: "##{id}-content",
      transition:
        {"tw:transition-all tw:transform tw:ease-in tw:duration-200",
         "tw:opacity-100 tw:translate-y-0 sm:tw:scale-100",
         "tw:opacity-0 tw:translate-y-4 sm:tw:translate-y-0 sm:tw:scale-95"}
    )
    |> JS.remove_class("tw:overflow-hidden", to: "body")
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
      class={["tw:relative tw:z-50", @class]}
      aria-labelledby={"#{@id}-title"}
      style={unless @show, do: "display: none;"}
    >
      <%!-- Backdrop --%>
      <div
        id={"#{@id}-backdrop"}
        class="tw:fixed tw:inset-0 tw:bg-grey-900/25 tw:transition-opacity"
        aria-hidden="true"
        phx-click={hide_modal(@id)}
      >
      </div>

      <%!-- Modal Container --%>
      <div class="tw:fixed tw:inset-0 tw:z-10 tw:overflow-y-auto">
        <div class="tw:flex tw:min-h-full tw:items-center tw:justify-center tw:p-4">
          <%!-- Modal Content --%>
          <div
            id={"#{@id}-content"}
            class={[
              "tw:relative tw:w-full tw:bg-white tw:rounded-[20px] tw:flex tw:flex-col tw:max-h-[calc(100vh-2rem)] tw:p-6",
              "tw:shadow-[0px_15px_50px_0px_rgba(3,9,19,0.4)]",
              modal_max_width(@max_width)
            ]}
            role="dialog"
            aria-modal="true"
            phx-click-away={hide_modal(@id)}
            phx-window-keydown={hide_modal(@id)}
            phx-key="escape"
          >
            <%!-- Close Button (top right) --%>
            <div class="tw:absolute tw:top-6 tw:right-6">
              <.icon_button
                icon="x-mark"
                variant="default"
                phx-click={hide_modal(@id)}
                aria-label="Close modal"
              />
            </div>

            <%!-- Header --%>
            <%= if @header != [] || @title do %>
              <div class="tw:mb-4 tw:pr-10">
                <%= if @header != [] do %>
                  {render_slot(@header)}
                <% else %>
                  <h2 id={"#{@id}-title"} class="tw:text-lg tw:font-semibold tw:text-grey-900">
                    {@title}
                  </h2>
                <% end %>
              </div>
            <% end %>

            <%!-- Body --%>
            <div class="tw:flex-1 tw:overflow-y-auto">
              {render_slot(@inner_block)}
            </div>

            <%!-- Footer --%>
            <%= if @footer != [] do %>
              <div class="tw:flex tw:items-center tw:justify-end tw:gap-3 tw:mt-6">
                {render_slot(@footer)}
              </div>
            <% end %>
          </div>
        </div>
      </div>
    </div>
    """
  end

  defp modal_max_width("sm"), do: "tw:max-w-sm"
  defp modal_max_width("md"), do: "tw:max-w-md"
  defp modal_max_width("lg"), do: "tw:max-w-lg"
  defp modal_max_width("xl"), do: "tw:max-w-xl"
  defp modal_max_width("2xl"), do: "tw:max-w-2xl"
  defp modal_max_width("3xl"), do: "tw:max-w-3xl"
  defp modal_max_width("4xl"), do: "tw:max-w-4xl"
end
