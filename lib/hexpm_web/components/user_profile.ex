defmodule HexpmWeb.Components.UserProfile do
  @moduledoc """
  User profile sidebar component with avatar, bio, stats, and contact information.
  """
  use Phoenix.Component
  import HexpmWeb.ViewHelpers
  import HexpmWeb.Components.Icons

  @doc """
  Renders the user profile sidebar with avatar, name, bio, and stats.
  """
  attr :user, :map, required: true
  attr :gravatar_email, :string, required: true
  attr :public_email, :string, default: nil
  attr :total_packages, :integer, required: true
  attr :total_downloads, :integer, required: true

  def user_sidebar(assigns) do
    ~H"""
    <div>
      <%!-- Avatar --%>
      <div class="flex justify-center mb-4">
        <img
          src={gravatar_url(@gravatar_email, :large)}
          alt={"#{@user.username} avatar"}
          class="w-30 h-30 rounded-full"
        />
      </div>

      <%!-- Name and Bio --%>
      <div class="text-center mb-6">
        <h2 class="text-grey-900 text-lg font-semibold mb-1">
          {@user.full_name || @user.username}
        </h2>
        <%= if @user.full_name && @user.username do %>
          <p class="text-grey-500 text-sm">
            {@user.username}
          </p>
        <% end %>
      </div>

      <%!-- Divider --%>
      <div class="border-t border-grey-200 mb-6"></div>

      <%!-- Stats Cards --%>
      <div class="grid grid-cols-2 gap-3 mb-6">
        <div class="bg-grey-100 border border-grey-200 rounded-lg p-3 text-center">
          <p class="text-grey-500 text-sm mb-1">Total Packages</p>
          <p class="text-grey-900 text-xl font-bold">{@total_packages}</p>
        </div>

        <div class="bg-grey-100 border border-grey-200 rounded-lg p-3 text-center">
          <p class="text-grey-500 text-sm mb-1">Total Downloads</p>
          <p class="text-grey-900 text-xl font-bold">
            {human_number_space(@total_downloads)}+
          </p>
        </div>
      </div>

      <%!-- Contact Info --%>
      <%= if @public_email || @user.handles do %>
        <div class="border-t border-grey-200 pt-6">
          <div class="flex gap-2.5 justify-center">
            <%!-- Public Email Icon --%>
            <%= if @public_email do %>
              <a
                href={"mailto:#{@public_email}"}
                class="group relative p-2 rounded-lg bg-grey-100 hover:bg-grey-200 transition-colors"
                title={@public_email}
              >
                {HexpmWeb.ViewIcons.icon(:heroicon, "envelope", class: "w-5 h-5 text-grey-700")}
                <span class="absolute bottom-full left-1/2 -translate-x-1/2 mb-2 px-3 py-1 bg-grey-900 text-white text-xs rounded whitespace-nowrap opacity-0 group-hover:opacity-100 transition-opacity pointer-events-none">
                  {@public_email}
                </span>
              </a>
            <% end %>

            <%!-- Social Media Icons --%>
            <%= for {service, handle, url} <- Hexpm.Accounts.UserHandles.render(@user) do %>
              <a
                href={url}
                class="group relative p-2 rounded-lg bg-grey-100 hover:bg-grey-200 transition-colors"
                target="_blank"
                rel="noopener noreferrer"
                title={"#{service}: #{handle}"}
              >
                <.social_icon icon={service_to_icon(service)} class="w-5 h-5 text-grey-700" />
                <span class="absolute bottom-full left-1/2 -translate-x-1/2 mb-2 px-3 py-1 bg-grey-900 text-white text-xs rounded whitespace-nowrap opacity-0 group-hover:opacity-100 transition-opacity pointer-events-none z-10">
                  {service}: {handle}
                </span>
              </a>
            <% end %>
          </div>
        </div>
      <% end %>
    </div>
    """
  end

  defp service_to_icon("Twitter"), do: :twitter
  defp service_to_icon("GitHub"), do: :github
  defp service_to_icon("Bluesky"), do: :bluesky
  defp service_to_icon("Elixir Forum"), do: :elixirforum
  defp service_to_icon("Slack"), do: :slack
  defp service_to_icon("Libera"), do: :freenode
  defp service_to_icon(_), do: :github
end
