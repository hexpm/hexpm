defmodule HexpmWeb.Components.Form do
  @moduledoc """
  Form component wrapper that properly handles form context for controller-based views.
  Ensures field names are correctly prefixed and form state is managed.
  """
  use Phoenix.Component
  use PhoenixHTMLHelpers

  @doc """
  Renders a simple_form with proper context handling using form_for.

  ## Examples

      <.simple_form for={@changeset} action={~p"/signup"} id="signup-form">
        <.text_input field={f[:username]} label="Username" />
        <.button type="submit">Submit</.button>
      </.simple_form>
  """
  attr :for, :any, required: true, doc: "The form source (changeset or params)"
  attr :action, :string, required: true
  attr :id, :string, required: true
  attr :method, :string, default: "post"
  attr :class, :string, default: ""
  attr :rest, :global

  slot :inner_block, required: true

  def simple_form(assigns) do
    ~H"""
    <%= form_for @for, @action, [id: @id, method: @method, class: @class] ++ Map.to_list(@rest), fn f -> %>
      {render_slot(@inner_block, f)}
    <% end %>
    """
  end
end
