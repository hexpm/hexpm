defmodule HexpmWeb.SharedAuthorizationView do
  use HexpmWeb, :view
  use Phoenix.Component

  alias Hexpm.Accounts.User
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

    assigns = %{
      categories: categories,
      grouped: grouped,
      style: style,
      current_user: current_user
    }

    ~H"""
    <.scope_group
      :for={category <- @categories}
      style={@style}
      category_name={format_category_name(category)}
      scopes={Map.get(@grouped, category)}
      current_user={@current_user}
    />
    """
  end

  defp scope_group(assigns) do
    ~H"""
    <%= if @style == :oauth do %>
      <div class="scope-group" style="margin-bottom: 20px;">
        <h5 class="scope-category-header" style="margin-bottom: 10px; color: #333; font-weight: 600;">
          {@category_name}
        </h5>
        <ul class="list-unstyled" style="margin-left: 20px;">
          <.render_scope_item
            :for={scope <- @scopes}
            scope={scope}
            style={@style}
            current_user={@current_user}
          />
        </ul>
      </div>
    <% else %>
      <div class="scope-group">
        <ul>
          <.render_scope_item
            :for={scope <- @scopes}
            scope={scope}
            style={@style}
            current_user={@current_user}
          />
        </ul>
      </div>
    <% end %>
    """
  end

  defp render_scope_item(assigns) do
    description = Permissions.scope_description(assigns.scope)
    requires_2fa = assigns.scope in ["api", "api:write"]
    checked = not (requires_2fa and not User.tfa_enabled?(assigns.current_user))

    assigns =
      assign(assigns, description: description, requires_2fa: requires_2fa, checked: checked)

    ~H"""
    <%= if @style == :oauth do %>
      <li class="scope-item" style="list-style: none; margin-bottom: 12px;">
        <label
          style="display: flex; align-items: flex-start; cursor: pointer; padding: 12px; border-radius: 8px; border: 2px solid #e9ecef; background-color: #f8f9fa; transition: all 0.2s ease;"
          onmouseover="this.style.borderColor='#0d6efd'; this.style.backgroundColor='#f0f7ff';"
          onmouseout="this.style.borderColor='#e9ecef'; this.style.backgroundColor='#f8f9fa';"
        >
          <input
            type="checkbox"
            name="selected_scopes[]"
            value={@scope}
            checked={@checked}
            style="margin-right: 12px; margin-top: 4px; width: 18px; height: 18px; cursor: pointer;"
            class="scope-checkbox"
          />
          <div style="flex: 1;">
            <div style="margin-bottom: 8px; display: flex; align-items: center; flex-wrap: wrap; gap: 8px;">
              <code
                class="scope-name"
                style="background-color: #e7f3ff; color: #0366d6; padding: 4px 10px; border-radius: 5px; font-size: 14px; font-weight: 600;"
              >
                {@scope}
              </code>
              <span
                :if={@requires_2fa}
                class="label label-warning"
                style="display: inline-flex; align-items: center; gap: 4px; padding: 4px 10px; border-radius: 5px; font-size: 12px; font-weight: 600; background-color: #fff3cd; color: #856404; border: 1px solid #ffeaa7; margin-left: 8px;"
              >
                <i class="fa fa-shield"></i> Requires 2FA
              </span>
            </div>
            <span class="scope-description" style="color: #6c757d; font-size: 14px; line-height: 1.5;">
              {@description}
            </span>
          </div>
        </label>
      </li>
    <% else %>
      <li style="list-style: none; margin-bottom: 12px;">
        <label
          style="display: flex; align-items: flex-start; cursor: pointer; padding: 14px; border-radius: 8px; border: 2px solid #e9ecef; background-color: #ffffff; transition: all 0.2s ease;"
          onmouseover="this.style.borderColor='#0d6efd'; this.style.backgroundColor='#f8f9fa';"
          onmouseout="this.style.borderColor='#e9ecef'; this.style.backgroundColor='#ffffff';"
        >
          <input
            type="checkbox"
            name="selected_scopes[]"
            value={@scope}
            checked={@checked}
            style="margin-right: 12px; margin-top: 4px; width: 18px; height: 18px; cursor: pointer;"
            class="scope-checkbox"
          />
          <div style="flex: 1;">
            <div style="margin-bottom: 8px; display: flex; align-items: center; flex-wrap: wrap; gap: 8px;">
              <code style="background-color: #e7f3ff; color: #0366d6; padding: 4px 10px; border-radius: 5px; font-size: 14px; font-weight: 600;">
                {@scope}
              </code>
              <span
                :if={@requires_2fa}
                class="label label-warning"
                style="display: inline-flex; align-items: center; gap: 4px; padding: 4px 10px; border-radius: 5px; font-size: 12px; font-weight: 600; background-color: #fff3cd; color: #856404; border: 1px solid #ffeaa7; margin-left: 8px;"
              >
                <i class="fa fa-shield"></i> Requires 2FA
              </span>
            </div>
            <span style="color: #6c757d; font-size: 14px; line-height: 1.6;">{@description}</span>
          </div>
        </label>
      </li>
    <% end %>
    """
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
