defmodule HexpmWeb.OAuthView do
  use HexpmWeb, :view

  alias Hexpm.Permissions

  @doc """
  Formats scopes for display on the OAuth authorization page.
  """
  def format_scopes(scopes, :summary) when is_list(scopes) do
    Permissions.format_summary(scopes)
  end


  @doc """
  Returns HTML-formatted grouped scopes.
  """
  def render_grouped_scopes(scopes) when is_list(scopes) do
    grouped = Permissions.group_scopes(scopes)

    # Define category order
    category_order = [:api, :repository, :package, :docs, :other]

    grouped_html = category_order
    |> Enum.filter(&Map.has_key?(grouped, &1))
    |> Enum.map(fn category ->
      category_scopes = Map.get(grouped, category)
      category_name = format_category_name(category)

      items = category_scopes
      |> Enum.map(fn scope ->
        description = Permissions.scope_description(scope)
        ~s(<li class="scope-item"><code class="scope-name">#{scope}</code> - <span class="scope-description">#{description}</span></li>)
      end)
      |> Enum.join("\n")

      """
      <div class="scope-group" style="margin-bottom: 20px;">
        <h5 class="scope-category-header" style="margin-bottom: 10px; color: #333; font-weight: 600;">#{category_name}</h5>
        <ul class="list-unstyled" style="margin-left: 20px;">#{items}</ul>
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
