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
      <div class="scope-group scope-group--oauth">
        <h5 class="scope-category-header">
          {@category_name}
        </h5>
        <ul class="list-unstyled scope-list">
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
      <li class="scope-item">
        <label class="scope-label">
          <input
            type="checkbox"
            name="selected_scopes[]"
            value={@scope}
            checked={@checked}
            class="scope-checkbox"
          />
          <div class="scope-content">
            <div class="scope-header">
              <code class="scope-name">
                {@scope}
              </code>
              <span
                :if={@requires_2fa}
                class="scope-requires-2fa"
              >
                <i class="fa fa-shield"></i> Requires 2FA
              </span>
            </div>
            <span class="scope-description">
              {@description}
            </span>
          </div>
        </label>
      </li>
    <% else %>
      <li class="scope-item">
        <label class="scope-label scope-label--device">
          <input
            type="checkbox"
            name="selected_scopes[]"
            value={@scope}
            checked={@checked}
            class="scope-checkbox"
          />
          <div class="scope-content">
            <div class="scope-header">
              <code class="scope-name">
                {@scope}
              </code>
              <span
                :if={@requires_2fa}
                class="scope-requires-2fa"
              >
                <i class="fa fa-shield"></i> Requires 2FA
              </span>
            </div>
            <span class="scope-description">{@description}</span>
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
