defmodule HexpmWeb.Components.Dropdown do
  @moduledoc """
  Reusable dropdown component for menus and selectors.
  """
  use Phoenix.Component
  alias Phoenix.LiveView.JS

  @doc """
  Renders a dropdown button with menu items.

  ## Examples

      <.dropdown id="sort-dropdown" label="Sort by">
        <.dropdown_item href="?sort=popular">Most Popular</.dropdown_item>
        <.dropdown_item href="?sort=downloads">Most Downloaded</.dropdown_item>
        <.dropdown_item href="?sort=newest">Newest First</.dropdown_item>
      </.dropdown>

      <.dropdown id="user-menu" label={@current_user.username} icon="user-circle">
        <.dropdown_item href="/settings">Settings</.dropdown_item>
        <.dropdown_item href="/logout">Logout</.dropdown_item>
      </.dropdown>
  """
  attr :id, :string, required: true
  attr :label, :string, required: true
  attr :icon, :string, default: "chevron-down"
  attr :button_class, :string, default: nil
  slot :inner_block, required: true

  def dropdown(assigns) do
    assigns =
      assign(
        assigns,
        :computed_button_class,
        assigns.button_class ||
          "tw:border tw:border-grey-200 tw:rounded-lg tw:px-3 tw:py-2 tw:text-grey-400 tw:text-sm tw:font-medium tw:flex tw:items-center tw:gap-1 tw:hover:border-grey-300 tw:transition-colors tw:bg-white"
      )

    ~H"""
    <div class="tw:relative" id={@id}>
      <button
        type="button"
        class={@computed_button_class}
        phx-click={toggle_dropdown(@id)}
      >
        {@label}
        {HexpmWeb.ViewIcons.icon(:heroicon, @icon, class: "tw:w-3.5 tw:h-3.5")}
      </button>

      <div
        id={"#{@id}-menu"}
        class="tw:hidden tw:absolute tw:right-0 tw:mt-2 tw:w-48 tw:bg-white tw:border tw:border-grey-200 tw:rounded-lg tw:shadow-lg tw:py-2 tw:z-10"
        phx-click-away={hide_dropdown(@id)}
      >
        {render_slot(@inner_block)}
      </div>
    </div>
    """
  end

  @doc """
  Renders a dropdown menu item.

  ## Examples

      <.dropdown_item href="/settings">Settings</.dropdown_item>
      <.dropdown_item href="/logout" class="tw:text-red-600">Logout</.dropdown_item>
  """
  attr :href, :string, required: true
  attr :class, :string, default: nil
  slot :inner_block, required: true

  def dropdown_item(assigns) do
    assigns =
      assign(
        assigns,
        :computed_class,
        assigns.class ||
          "tw:block tw:px-4 tw:py-2 tw:text-sm tw:hover:bg-grey-50 tw:text-grey-700 tw:hover:text-grey-900"
      )

    ~H"""
    <a href={@href} class={@computed_class}>
      {render_slot(@inner_block)}
    </a>
    """
  end

  defp toggle_dropdown(id) do
    JS.toggle(to: "##{id}-menu")
  end

  defp hide_dropdown(id) do
    JS.hide(to: "##{id}-menu")
  end
end
