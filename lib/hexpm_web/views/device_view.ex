defmodule HexpmWeb.DeviceView do
  use HexpmWeb, :view

  alias Hexpm.Permissions

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
  Formats scopes for display on the device authorization page.
  """
  def format_scopes(scopes, :summary) when is_list(scopes) do
    Permissions.format_summary(scopes)
  end


  @doc """
  Returns HTML-formatted grouped scopes.
  """
  def render_grouped_scopes(scopes) when is_list(scopes) do
    grouped_html = Permissions.group_scopes(scopes)
    |> Enum.map(fn {category, category_scopes} ->
      category_name = format_category_name(category)
      items = category_scopes
      |> Enum.map(fn scope ->
        description = Permissions.scope_description(scope)
        ~s(<li><code>#{scope}</code> - #{description}</li>)
      end)
      |> Enum.join("\n")

      """
      <div class="scope-group">
        <h5>#{category_name}</h5>
        <ul>#{items}</ul>
      </div>
      """
    end)
    |> Enum.join("\n")

    raw(grouped_html)
  end

  defp format_category_name(category) do
    case category do
      :api -> "API Access"
      :repository -> "Repository Access"
      :package -> "Package Management"
      :docs -> "Documentation Access"
      _ -> to_string(category) |> String.capitalize()
    end
  end
end
