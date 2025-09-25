defmodule HexpmWeb.SharedAuthorizationView do
  use HexpmWeb, :view

  alias Hexpm.Permissions

  @doc """
  Formats scopes for display on authorization pages.
  """
  def format_scopes(scopes, :summary) when is_list(scopes) do
    Permissions.format_summary(scopes)
  end

  @doc """
  Returns HTML-formatted grouped scopes with checkboxes.

  Style can be:
    - :oauth - Full styling with category headers and ordering
    - :device - Simple styling without category headers
  """
  def render_grouped_scopes(scopes, style \\ :device) when is_list(scopes) do
    grouped = Permissions.group_scopes(scopes)

    # Get categories in the specified order or all categories
    categories =
      if style == :oauth do
        [:api, :repository, :package, :docs, :other]
        |> Enum.filter(&Map.has_key?(grouped, &1))
      else
        Map.keys(grouped)
      end

    grouped_html =
      categories
      |> Enum.map(fn category ->
        category_scopes = Map.get(grouped, category)

        items =
          category_scopes
          |> Enum.map(fn scope ->
            render_scope_item(scope, style)
          end)
          |> Enum.join("\n")

        if style == :oauth do
          category_name = format_category_name(category)

          """
          <div class="scope-group" style="margin-bottom: 20px;">
            <h5 class="scope-category-header" style="margin-bottom: 10px; color: #333; font-weight: 600;">#{category_name}</h5>
            <ul class="list-unstyled" style="margin-left: 20px;">#{items}</ul>
          </div>
          """
        else
          """
          <div class="scope-group">
            <ul>#{items}</ul>
          </div>
          """
        end
      end)
      |> Enum.join("\n")

    raw(grouped_html)
  end

  defp render_scope_item(scope, style) do
    description = Permissions.scope_description(scope)

    if style == :oauth do
      ~s(<li class="scope-item" style="list-style: none; margin-bottom: 10px;">
        <label style="display: flex; align-items: flex-start; cursor: pointer;">
          <input type="checkbox" name="selected_scopes[]" value="#{scope}" checked="checked" style="margin-right: 10px; margin-top: 3px;" class="scope-checkbox">
          <div>
            <code class="scope-name">#{scope}</code> - <span class="scope-description">#{description}</span>
          </div>
        </label>
      </li>)
    else
      ~s(<li style="list-style: none; margin-bottom: 10px;">
        <label style="display: flex; align-items: flex-start; cursor: pointer;">
          <input type="checkbox" name="selected_scopes[]" value="#{scope}" checked="checked" style="margin-right: 10px; margin-top: 3px;" class="scope-checkbox">
          <div>
            <code>#{scope}</code> - #{description}
          </div>
        </label>
      </li>)
    end
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
