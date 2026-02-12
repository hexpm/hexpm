defmodule HexpmWeb.Components.SocialInput do
  @moduledoc """
  Reusable component for social media input fields with inline icons.
  """
  use Phoenix.Component

  @doc """
  Renders a social media input field with an icon.

  ## Examples

      <.social_input
        form={f}
        field={:twitter}
        icon={:twitter}
        placeholder="your_username"
      />
  """
  attr :form, :any, required: true
  attr :field, :atom, required: true
  attr :icon, :atom, required: true
  attr :placeholder, :string, default: "your_username"

  def social_input(assigns) do
    # Get the form field for error handling
    field = assigns.form[assigns.field]
    errors = if field, do: field.errors, else: []

    assigns = assign(assigns, :has_errors, errors != [])

    ~H"""
    <div>
      <div class={[
        "tw:flex tw:items-center tw:border tw:rounded-lg tw:focus-within:ring-2 tw:transition-colors",
        @has_errors && "tw:border-red-300 tw:focus-within:ring-red-600",
        !@has_errors &&
          "tw:border-grey-200 tw:focus-within:ring-purple-600 tw:focus-within:border-transparent"
      ]}>
        <div class="tw:flex tw:items-center tw:px-3 tw:py-2 tw:border-r tw:border-grey-200">
          {render_icon(@icon)}
          <span class="tw:text-grey-500 tw:text-sm tw:mx-2">/</span>
        </div>
        <input
          type="text"
          id={@form[@field].id}
          name={@form[@field].name}
          value={@form[@field].value}
          placeholder={@placeholder}
          class="tw:flex-1 tw:px-3 tw:py-2 tw:text-grey-900 tw:border-0 focus:tw:outline-none focus:tw:ring-0 tw:bg-transparent"
        />
      </div>
      <%= if @has_errors do %>
        <div class="tw:mt-1">
          <p
            :for={msg <- Enum.map(@form[@field].errors, &translate_error/1)}
            class="tw:flex tw:items-center tw:gap-1 tw:text-sm tw:text-red-600"
          >
            {HexpmWeb.ViewIcons.icon(:heroicon, "exclamation-circle", width: 16, height: 16)}
            <span>{msg}</span>
          </p>
        </div>
      <% end %>
    </div>
    """
  end

  defp render_icon(:twitter) do
    assigns = %{}

    ~H"""
    <HexpmWeb.Components.Icons.twitter_icon class="tw:w-5 tw:h-5 tw:text-grey-600" />
    """
  end

  defp render_icon(:bluesky) do
    assigns = %{}

    ~H"""
    <HexpmWeb.Components.Icons.bluesky_icon class="tw:w-5 tw:h-5 tw:text-grey-600" />
    """
  end

  defp render_icon(:github) do
    assigns = %{}

    ~H"""
    <HexpmWeb.Components.Icons.github_icon class="tw:w-5 tw:h-5 tw:text-grey-600" />
    """
  end

  defp render_icon(:elixirforum) do
    assigns = %{}

    ~H"""
    <HexpmWeb.Components.Icons.elixirforum_icon class="tw:w-5 tw:h-5 tw:text-grey-600" />
    """
  end

  defp render_icon(:libera) do
    assigns = %{}

    ~H"""
    <HexpmWeb.Components.Icons.libera_icon class="tw:w-5 tw:h-5 tw:text-grey-600" />
    """
  end

  defp translate_error({msg, opts}) do
    Enum.reduce(opts, msg, fn {key, value}, acc ->
      String.replace(acc, "%{#{key}}", to_string(value))
    end)
  end

  defp translate_error(msg) when is_binary(msg), do: msg
end
