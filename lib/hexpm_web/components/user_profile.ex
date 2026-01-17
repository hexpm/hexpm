defmodule HexpmWeb.Components.UserProfile do
  @moduledoc """
  User profile sidebar component with avatar, bio, stats, and contact information.
  """
  use Phoenix.Component
  import HexpmWeb.ViewHelpers

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
    <div class="tw:rounded-lg tw:p-6">
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
          <p class="tw:text-grey-900 tw:text-xl tw:font-bold">{human_number_space(@total_downloads)}+</p>
        </div>
      </div>

      <%!-- Contact Info --%>
      <%= if @public_email || @user.handles do %>
        <div class="tw:border-t tw:border-grey-200 tw:pt-6">
          <ul class="tw:space-y-2 tw:text-sm">
            <%= if @public_email do %>
              <li>
                <a
                  href={"mailto:#{@public_email}"}
                  class="tw:text-blue-500 tw:hover:text-blue-600 tw:underline"
                >
                  {@public_email}
                </a>
              </li>
            <% end %>

            <%= for {service, handle, url} <- Hexpm.Accounts.UserHandles.render(@user) do %>
              <li>
                <a
                  href={url}
                  class="tw:text-blue-500 tw:hover:text-blue-600 tw:underline"
                  target="_blank"
                  rel="noopener noreferrer"
                >
                  {handle}
                </a>
                <span class="tw:text-grey-500"> on {service}</span>
              </li>
            <% end %>
          </ul>
        </div>
      <% end %>
    </div>
    """
  end
end
