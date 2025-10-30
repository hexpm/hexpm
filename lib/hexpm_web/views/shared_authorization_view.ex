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
  def render_grouped_scopes(scopes, style \\ :device, current_user \\ nil) when is_list(scopes) do
    grouped = Permissions.group_scopes(scopes)

    # Get categories in the specified order or all categories
    categories =
      if style == :oauth do
        [:api, :repository, :package, :docs]
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
            render_scope_item(scope, style, current_user)
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

  defp render_scope_item(scope, style, current_user) do
    description = Permissions.scope_description(scope)
    requires_2fa = scope in ["api", "api:write"]

    checked =
      if requires_2fa and not User.tfa_enabled?(current_user) do
        ""
      else
        ~s(checked="checked")
      end

    tfa_badge =
      if requires_2fa do
        ~s(<span class="label label-warning" style="display: inline-flex; align-items: center; gap: 4px; padding: 4px 10px; border-radius: 5px; font-size: 12px; font-weight: 600; background-color: #fff3cd; color: #856404; border: 1px solid #ffeaa7; margin-left: 8px;"><i class="fa fa-shield"></i> Requires 2FA</span>)
      else
        ""
      end

    if style == :oauth do
      ~s(<li class="scope-item" style="list-style: none; margin-bottom: 12px;">
        <label style="display: flex; align-items: flex-start; cursor: pointer; padding: 12px; border-radius: 8px; border: 2px solid #e9ecef; background-color: #f8f9fa; transition: all 0.2s ease;" onmouseover="this.style.borderColor='#0d6efd'; this.style.backgroundColor='#f0f7ff';" onmouseout="this.style.borderColor='#e9ecef'; this.style.backgroundColor='#f8f9fa';">
          <input type="checkbox" name="selected_scopes[]" value="#{scope}" #{checked} style="margin-right: 12px; margin-top: 4px; width: 18px; height: 18px; cursor: pointer;" class="scope-checkbox">
          <div style="flex: 1;">
            <div style="margin-bottom: 8px; display: flex; align-items: center; flex-wrap: wrap; gap: 8px;">
              <code class="scope-name" style="background-color: #e7f3ff; color: #0366d6; padding: 4px 10px; border-radius: 5px; font-size: 14px; font-weight: 600;">#{scope}</code>#{tfa_badge}
            </div>
            <span class="scope-description" style="color: #6c757d; font-size: 14px; line-height: 1.5;">#{description}</span>
          </div>
        </label>
      </li>)
    else
      ~s(<li style="list-style: none; margin-bottom: 12px;">
        <label style="display: flex; align-items: flex-start; cursor: pointer; padding: 14px; border-radius: 8px; border: 2px solid #e9ecef; background-color: #ffffff; transition: all 0.2s ease;" onmouseover="this.style.borderColor='#0d6efd'; this.style.backgroundColor='#f8f9fa';" onmouseout="this.style.borderColor='#e9ecef'; this.style.backgroundColor='#ffffff';">
          <input type="checkbox" name="selected_scopes[]" value="#{scope}" #{checked} style="margin-right: 12px; margin-top: 4px; width: 18px; height: 18px; cursor: pointer;" class="scope-checkbox">
          <div style="flex: 1;">
            <div style="margin-bottom: 8px; display: flex; align-items: center; flex-wrap: wrap; gap: 8px;">
              <code style="background-color: #e7f3ff; color: #0366d6; padding: 4px 10px; border-radius: 5px; font-size: 14px; font-weight: 600;">#{scope}</code>#{tfa_badge}
            </div>
            <span style="color: #6c757d; font-size: 14px; line-height: 1.6;">#{description}</span>
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
