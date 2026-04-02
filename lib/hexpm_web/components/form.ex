defmodule HexpmWeb.Components.Form do
  @moduledoc """
  Form component wrapper that properly handles form context for controller-based views.
  Ensures field names are correctly prefixed and form state is managed.
  """
  use Phoenix.Component
  use PhoenixHTMLHelpers

  alias HexpmWeb.Plugs.Sudo

  @doc """
  Renders a simple_form with proper context handling using form_for.

  ## Examples

      <.simple_form for={@changeset} action={~p"/signup"} id="signup-form">
        <.text_input field={f[:username]} label="Username" />
        <.button type="submit">Submit</.button>
      </.simple_form>
  """
  attr :action, :string, required: true
  attr :class, :string, default: ""
  attr :for, :any, required: true, doc: "The form source (changeset or params)"
  attr :id, :string, required: true
  attr :method, :string, default: "post"
  attr :rest, :global

  slot :inner_block, required: true

  def simple_form(assigns) do
    ~H"""
    <%= form_for @for, @action, [id: @id, method: @method, class: @class] ++ Map.to_list(@rest), fn f -> %>
      {render_slot(@inner_block, f)}
    <% end %>
    """
  end

  @doc """
  Renders a form that includes a signed sudo token.

  Wraps Phoenix's `<.form>` component, which handles CSRF tokens and method
  overrides, and adds a sudo form token bound to the form's method and action.
  Use this for all forms on sudo-protected pages so submissions work even if
  the sudo session expires between page load and submit.

  ## Examples

      <.sudo_form conn={@conn} action={~p"/dashboard/security/change-password"}>
        <input type="password" name="user[password]" />
        <.button type="submit">Change Password</.button>
      </.sudo_form>

      <.sudo_form conn={@conn} action={~p"/dashboard/keys"} method="delete">
        <input type="hidden" name="key_name" value="my-key" />
        <.button type="submit">Delete</.button>
      </.sudo_form>
  """
  attr :current_user, :map, required: true
  attr :action, :string, required: true
  attr :for, :any, default: %{}
  attr :method, :string, default: "post"
  attr :rest, :global, include: ~w(id class phx-hook)
  slot :inner_block, required: true

  def sudo_form(assigns) do
    token_method = assigns.method |> String.upcase()
    sudo_token = Sudo.generate_form_token(assigns.current_user.id, token_method, assigns.action)
    assigns = assign(assigns, :sudo_token, sudo_token)

    ~H"""
    <%= form_for @for, @action, [method: @method] ++ Map.to_list(@rest), fn f -> %>
      <input type="hidden" name="_sudo_token" value={@sudo_token} />
      {render_slot(@inner_block, f)}
    <% end %>
    """
  end
end
