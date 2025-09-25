defmodule HexpmWeb.DeviceView do
  use HexpmWeb, :view

  alias HexpmWeb.SharedAuthorizationView

  @doc """
  Formats a user code for display by inserting a hyphen in the middle.
  Converts "ABCD1234" to "ABCD-1234" for better readability.
  """
  def format_user_code(nil), do: ""
  def format_user_code(""), do: ""

  def format_user_code(user_code) when byte_size(user_code) == 8 do
    String.slice(user_code, 0, 4) <> "-" <> String.slice(user_code, 4, 4)
  end

  def format_user_code(user_code), do: user_code

  @doc """
  Normalizes user input by removing dashes and converting to uppercase.
  This allows users to enter codes with or without formatting.
  """
  def normalize_user_code(nil), do: ""
  def normalize_user_code(""), do: ""

  def normalize_user_code(user_code) when is_binary(user_code) do
    user_code
    |> String.replace("-", "")
    |> String.upcase()
  end

  @doc """
  Delegates to SharedAuthorizationView for formatting scopes.
  """
  defdelegate format_scopes(scopes, format), to: SharedAuthorizationView

  @doc """
  Renders grouped scopes using SharedAuthorizationView.
  """
  def render_grouped_scopes(scopes, current_user) when is_list(scopes) do
    SharedAuthorizationView.render_grouped_scopes(scopes, :device, current_user)
  end

  @doc """
  Prepares authorization data for the shared partial.
  """
  def authorization_assigns(conn, device_code) do
    client_name =
      if device_code.client do
        device_code.client.name
      else
        device_code.client_id
      end

    current_user = conn.assigns[:current_user]

    %{
      client_name: client_name,
      scopes: device_code.scopes,
      render_scopes: &render_grouped_scopes(&1, current_user),
      format_summary: &format_scopes(&1, :summary),
      form_action: ~p"/oauth/device",
      hidden_fields: [{"user_code", device_code.user_code}],
      approve_value: "authorize",
      deny_value: "deny",
      with_checkboxes: true,
      auth_title: "Authorize Device",
      auth_description: "The device",
      current_user: current_user
    }
  end
end
