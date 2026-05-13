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
      <ul class="list-none space-y-1">
        <.render_scope_item
          :for={scope <- @scopes}
          scope={scope}
          style={@style}
          current_user={@current_user}
        />
      </ul>
    <% end %>
    """
  end

  defp render_scope_item(assigns) do
    description = Permissions.scope_description(assigns.scope)
    requires_2fa = assigns.scope in ["api", "api:write"]
    has_2fa = User.tfa_enabled?(assigns.current_user)
    required = assigns.scope == "api:read"
    disabled = required or (requires_2fa and not has_2fa)
    checked = required or not disabled

    assigns =
      assign(assigns,
        description: description,
        requires_2fa: requires_2fa,
        required: required,
        checked: checked,
        disabled: disabled
      )

    ~H"""
    <%= if @style == :oauth do %>
      <li class="scope-item">
        <label class="scope-label">
          <input
            type="checkbox"
            name="selected_scopes[]"
            value={@scope}
            checked={@checked}
            disabled={@disabled}
            class="scope-checkbox"
          />
          <input :if={@required} type="hidden" name="selected_scopes[]" value={@scope} />
          <div class="scope-content">
            <div class="scope-header">
              <code class="scope-name">
                {@scope}
              </code>
              <span
                :if={@required}
                class="scope-required"
              >
                Required
              </span>
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
      <li class="flex items-start gap-3 py-2">
        <label class={[
          "flex items-start gap-3",
          @disabled && "cursor-not-allowed",
          !@disabled && "cursor-pointer",
          @disabled && !@required && "opacity-60"
        ]}>
          <input
            type="checkbox"
            name="selected_scopes[]"
            value={@scope}
            checked={@checked}
            disabled={@disabled}
            class="scope-checkbox mt-1 h-4 w-4 rounded border-grey-300 dark:border-grey-600 bg-white dark:bg-grey-900 text-primary-600 focus:ring-primary-500 dark:focus:ring-primary-400"
          />
          <input :if={@required} type="hidden" name="selected_scopes[]" value={@scope} />
          <div>
            <div class="flex items-center gap-2">
              <code class="text-sm font-semibold text-grey-900 dark:text-grey-100">{@scope}</code>
              <span
                :if={@required}
                class="inline-flex items-center rounded-full bg-grey-100 dark:bg-grey-700 px-2 py-0.5 text-xs font-medium text-grey-700 dark:text-grey-200"
              >
                Required
              </span>
              <span
                :if={@requires_2fa}
                class="inline-flex items-center rounded-full bg-yellow-100 dark:bg-yellow-900/30 px-2 py-0.5 text-xs font-medium text-yellow-800 dark:text-yellow-200"
              >
                Requires 2FA
              </span>
            </div>
            <span class="text-sm text-grey-600 dark:text-grey-300">{@description}</span>
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
