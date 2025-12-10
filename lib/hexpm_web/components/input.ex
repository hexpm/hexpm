defmodule HexpmWeb.Components.Input do
  @moduledoc """
  Reusable form input components.
  """
  use Phoenix.Component
  alias Phoenix.LiveView.JS
  import HexpmWeb.ViewIcons, only: [icon: 3]

  @doc """
  Renders a password input with visibility toggle.

  ## Examples

      <.password_input id="password" name="password" />
      <.password_input id="password" name="password" class="custom-class" />
  """
  attr :id, :string, required: true
  attr :name, :string, required: true
  attr :class, :string, default: ""
  attr :placeholder, :string, default: ""

  def password_input(assigns) do
    ~H"""
    <div class="tw:relative">
      <input
        id={@id}
        type="password"
        name={@name}
        placeholder={@placeholder}
        class={[
          "tw:w-full tw:h-12 tw:bg-white tw:border tw:border-grey-200 tw:rounded tw:px-3 tw:pr-10",
          "tw:text-grey-900 tw:placeholder:text-grey-300",
          "tw:focus:outline-none tw:focus:border-primary-600 tw:focus:ring-1 tw:focus:ring-primary-600",
          @class
        ]}
      />
      <button
        type="button"
        class="tw:absolute tw:right-3 tw:top-1/2 tw:-translate-y-1/2 tw:text-grey-400 tw:hover:text-grey-600 tw:transition-colors"
        phx-click={toggle_password_visibility(@id)}
        aria-label="Toggle password visibility"
      >
        <span id={"#{@id}-eye-icon"}>
          {icon(:heroicon, "eye", width: 16, height: 16)}
        </span>
        <span id={"#{@id}-eye-slash-icon"} class="tw:hidden">
          {icon(:heroicon, "eye-slash", width: 16, height: 16)}
        </span>
      </button>
    </div>
    """
  end

  defp toggle_password_visibility(input_id) do
    JS.toggle_attribute({"type", "text", "password"}, to: "##{input_id}")
    |> JS.toggle_class("tw:hidden", to: "##{input_id}-eye-icon")
    |> JS.toggle_class("tw:hidden", to: "##{input_id}-eye-slash-icon")
  end
end
