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

  Automatically injects both the CSRF token and a sudo form token bound to the
  form's method and action. Use this for all forms on sudo-protected pages so
  submissions work even if the sudo session expires between page load and submit.

  The `method` attribute accepts any HTTP method. For non-GET/POST methods (like
  "delete"), the component renders `method="post"` with a `_method` override,
  matching Phoenix's standard form behavior.

  ## Examples

      <.sudo_form conn={@conn} action={~p"/dashboard/security/change-password"} method="post">
        <input type="password" name="user[password]" />
        <.button type="submit">Change Password</.button>
      </.sudo_form>

      <.sudo_form conn={@conn} action={~p"/dashboard/keys"} method="delete">
        <input type="hidden" name="key_name" value="my-key" />
        <.button type="submit">Delete</.button>
      </.sudo_form>
  """
  attr :conn, Plug.Conn, required: true
  attr :action, :string, required: true
  attr :method, :string, default: "post"
  attr :rest, :global, include: ~w(id class)
  slot :inner_block, required: true

  def sudo_form(assigns) do
    token_method = assigns.method |> String.upcase()

    {form_method, method_override} =
      case token_method do
        method when method in ["GET", "POST"] -> {String.downcase(method), nil}
        method -> {"post", method}
      end

    sudo_token = Sudo.generate_form_token(assigns.conn, token_method, assigns.action)

    assigns =
      assigns
      |> assign(:form_method, form_method)
      |> assign(:method_override, method_override)
      |> assign(:csrf_token, Plug.CSRFProtection.get_csrf_token())
      |> assign(:sudo_token, sudo_token)

    ~H"""
    <form action={@action} method={@form_method} {@rest}>
      <input type="hidden" name="_csrf_token" value={@csrf_token} />
      <input :if={@method_override} type="hidden" name="_method" value={@method_override} />
      <input type="hidden" name="_sudo_token" value={@sudo_token} />
      {render_slot(@inner_block)}
    </form>
    """
  end
end
