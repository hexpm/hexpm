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
      <div class="tw:flex tw:justify-center tw:mb-4">
        <img
          src={gravatar_url(@gravatar_email, :large)}
          alt={"#{@user.username} avatar"}
          class="tw:w-30 tw:h-30 tw:rounded-full"
        />
      </div>

      <%!-- Name and Bio --%>
      <div class="tw:text-center tw:mb-6">
        <h2 class="tw:text-grey-900 tw:text-lg tw:font-semibold tw:mb-1">
          {@user.full_name || @user.username}
        </h2>
        <%= if @user.full_name && @user.username do %>
          <p class="tw:text-grey-500 tw:text-sm">
            {@user.username}
          </p>
        <% end %>
      </div>

      <%!-- Divider --%>
      <div class="tw:border-t tw:border-grey-200 tw:mb-6"></div>

      <%!-- Stats Cards --%>
      <div class="tw:grid tw:grid-cols-2 tw:gap-3 tw:mb-6">
        <div class="tw:bg-grey-100 tw:border tw:border-grey-200 tw:rounded-lg tw:p-3 tw:text-center">
          <p class="tw:text-grey-500 tw:text-sm tw:mb-1">Total Packages</p>
          <p class="tw:text-grey-900 tw:text-xl tw:font-bold">{@total_packages}</p>
        </div>

        <div class="tw:bg-grey-100 tw:border tw:border-grey-200 tw:rounded-lg tw:p-3 tw:text-center">
          <p class="tw:text-grey-500 tw:text-sm tw:mb-1">Total Downloads</p>
          <p class="tw:text-grey-900 tw:text-xl tw:font-bold">
            {human_number_space(@total_downloads)}+
          </p>
        </div>
      </div>

      <%!-- Contact Info --%>
      <%= if @public_email || @user.handles do %>
        <div class="tw:border-t tw:border-grey-200 tw:pt-6">
          <div class="tw:flex tw:gap-2.5 tw:justify-center">
            <%!-- Public Email Icon --%>
            <%= if @public_email do %>
              <a
                href={"mailto:#{@public_email}"}
                class="tw:group tw:relative tw:p-2 tw:rounded-lg tw:bg-grey-100 tw:hover:bg-grey-200 tw:transition-colors"
                title={@public_email}
              >
                {HexpmWeb.ViewIcons.icon(:heroicon, "envelope",
                  class: "tw:w-5 tw:h-5 tw:text-grey-700"
                )}
                <span class="tw:absolute tw:bottom-full tw:left-1/2 tw:-translate-x-1/2 tw:mb-2 tw:px-3 tw:py-1 tw:bg-grey-900 tw:text-white tw:text-xs tw:rounded tw:whitespace-nowrap tw:opacity-0 tw:group-hover:opacity-100 tw:transition-opacity tw:pointer-events-none">
                  {@public_email}
                </span>
              </a>
            <% end %>

            <%!-- Social Media Icons --%>
            <%= for {service, handle, url} <- Hexpm.Accounts.UserHandles.render(@user) do %>
              <a
                href={url}
                class="tw:group tw:relative tw:p-2 tw:rounded-lg tw:bg-grey-100 tw:hover:bg-grey-200 tw:transition-colors"
                target="_blank"
                rel="noopener noreferrer"
                title={"#{service}: #{handle}"}
              >
                <.social_icon icon={service_to_icon(service)} class="tw:w-5 tw:h-5 tw:text-grey-700" />
                <span class="tw:absolute tw:bottom-full tw:left-1/2 tw:-translate-x-1/2 tw:mb-2 tw:px-3 tw:py-1 tw:bg-grey-900 tw:text-white tw:text-xs tw:rounded tw:whitespace-nowrap tw:opacity-0 tw:group-hover:opacity-100 tw:transition-opacity tw:pointer-events-none tw:z-10">
                  {handle}
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
