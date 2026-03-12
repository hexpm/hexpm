defmodule HexpmWeb.Dashboard.Organization.Components.ProfileTab do
  @moduledoc """
  Profile tab content for the organization dashboard.
  """
  use Phoenix.Component
  use PhoenixHTMLHelpers
  use Hexpm.Shared

  use Phoenix.VerifiedRoutes,
    endpoint: HexpmWeb.Endpoint,
    router: HexpmWeb.Router,
    statics: HexpmWeb.static_paths()

  import HexpmWeb.Components.Buttons, only: [button: 1, text_link: 1]
  import HexpmWeb.Components.Input, only: [text_input: 1]
  import HexpmWeb.Components.SocialInput, only: [social_input: 1]

  attr :changeset, :any, required: true
  attr :gravatar_email, :string, default: nil
  attr :organization, :map, required: true
  attr :public_email, :string, default: nil

  def profile_tab(assigns) do
    assigns =
      assign_new(assigns, :org_gravatar_email, fn ->
        if assigns.organization.user do
          Hexpm.Accounts.User.email(assigns.organization.user, :gravatar)
        end
      end)

    ~H"""
    <div class="tw:bg-white tw:border tw:border-grey-200 tw:rounded-lg tw:p-8">
      <h2 class="tw:text-grey-900 tw:text-xl tw:font-semibold tw:mb-8">
        Public profile
      </h2>

      <%= if @organization.user do %>
        <%!-- Profile Picture --%>
        <div class="tw:flex tw:items-start tw:gap-6 tw:mb-8 tw:pb-8 tw:border-b tw:border-grey-200">
          <%= if @org_gravatar_email do %>
            <img
              src={HexpmWeb.ViewHelpers.gravatar_url(@org_gravatar_email, :large)}
              alt="Organization avatar"
              class="tw:w-24 tw:h-24 tw:rounded-full tw:flex-shrink-0"
            />
          <% else %>
            <div class="tw:w-24 tw:h-24 tw:rounded-full tw:bg-grey-100 tw:flex tw:items-center tw:justify-center tw:flex-shrink-0">
              {HexpmWeb.ViewIcons.icon(:heroicon, "user-circle", class: "tw:w-16 tw:h-16 tw:text-grey-400")}
            </div>
          <% end %>

          <div class="tw:flex-1">
            <.text_link href="https://en.gravatar.com/emails/" variant="purple" class="tw:text-sm">
              Change Photo
            </.text_link>
            <p class="tw:text-grey-500 tw:text-sm tw:mt-2">
              <%= if @org_gravatar_email do %>
                <.text_link href="https://en.gravatar.com/emails/" variant="purple">Gravatar</.text_link>
                is used to display your organization's profile picture. You can choose your Gravatar email below or
                go to Gravatar to change the image.
              <% else %>
                <.text_link href="https://en.gravatar.com/emails/" variant="purple">Gravatar</.text_link>
                is used to display your organization's profile picture.
                Choose a Gravatar email address below to show your avatar on your profile.
              <% end %>
            </p>
          </div>
        </div>

        <%= form_for @changeset, ~p"/dashboard/orgs/#{@organization}/profile", [method: :post], fn f -> %>
          <div class="tw:space-y-6">
            <.text_input field={f[:full_name]} label="Full Name" />

            <.text_input
              field={f[:public_email]}
              label="Public Email"
              value={@public_email}
              placeholder="Your organization's public email"
            />

            <.text_input
              field={f[:gravatar_email]}
              label="Gravatar Email"
              value={@gravatar_email}
              placeholder="Your organization's Gravatar email"
            />

            <%= inputs_for(f, :handles, fn fh -> %>
              <div class="tw:border-t tw:border-grey-200 tw:pt-6 tw:mt-6">
                <h3 class="tw:text-grey-900 tw:text-sm tw:font-semibold tw:uppercase tw:tracking-wider tw:mb-6">
                  Socials
                </h3>
                <div class="tw:space-y-5">
                  <.social_input form={fh} field={:twitter} icon={:twitter} placeholder="your_username" />
                  <.social_input form={fh} field={:bluesky} icon={:bluesky} placeholder="your_username.bsky.social" />
                  <.social_input form={fh} field={:github} icon={:github} placeholder="your_username" />
                  <.social_input form={fh} field={:elixirforum} icon={:elixirforum} placeholder="your_username" />
                </div>
              </div>
            <% end) %>

            <div class="tw:flex tw:justify-start tw:pt-6">
              <.button type="submit" variant="primary">Save Changes</.button>
            </div>
          </div>
        <% end %>
      <% else %>
        <div class="tw:rounded-lg tw:bg-amber-50 tw:border tw:border-amber-200 tw:p-4 tw:text-sm tw:text-amber-800">
          There is no profile associated with your organization. To enable the profile, your organization needs to be migrated. Please contact{" "}
          <a href="mailto:support@hex.pm" class="tw:underline tw:hover:text-amber-900">support@hex.pm</a>.
        </div>
      <% end %>
    </div>
    """
  end
end
