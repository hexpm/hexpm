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
    <div class="bg-white border border-grey-200 rounded-lg p-8">
      <h2 class="text-grey-900 text-xl font-semibold mb-8">
        Public profile
      </h2>

      <%= if @organization.user do %>
        <%!-- Profile Picture --%>
        <div class="flex items-start gap-6 mb-8 pb-8 border-b border-grey-200">
          <%= if @org_gravatar_email do %>
            <img
              src={HexpmWeb.ViewHelpers.gravatar_url(@org_gravatar_email, :large)}
              alt="Organization avatar"
              class="w-24 h-24 rounded-full flex-shrink-0"
            />
          <% else %>
            <div class="w-24 h-24 rounded-full bg-grey-100 flex items-center justify-center flex-shrink-0">
              {HexpmWeb.ViewIcons.icon(:heroicon, "user-circle", class: "w-16 h-16 text-grey-400")}
            </div>
          <% end %>

          <div class="flex-1">
            <.text_link href="https://en.gravatar.com/emails/" variant="purple" class="text-sm">
              Change Photo
            </.text_link>
            <p class="text-grey-500 text-sm mt-2">
              <%= if @org_gravatar_email do %>
                <.text_link href="https://en.gravatar.com/emails/" variant="purple">
                  Gravatar
                </.text_link>
                is used to display your organization's profile picture. You can choose your Gravatar email below or
                go to Gravatar to change the image.
              <% else %>
                <.text_link href="https://en.gravatar.com/emails/" variant="purple">
                  Gravatar
                </.text_link>
                is used to display your organization's profile picture.
                Choose a Gravatar email address below to show your avatar on your profile.
              <% end %>
            </p>
          </div>
        </div>

        <%= form_for @changeset, ~p"/dashboard/orgs/#{@organization}/profile", [method: :post], fn f -> %>
          <div class="space-y-6">
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
              <div class="border-t border-grey-200 pt-6 mt-6">
                <h3 class="text-grey-900 text-sm font-semibold uppercase tracking-wider mb-6">
                  Socials
                </h3>
                <div class="space-y-5">
                  <.social_input
                    form={fh}
                    field={:twitter}
                    icon={:twitter}
                    label="Twitter"
                    placeholder="Twitter username"
                  />
                  <.social_input
                    form={fh}
                    field={:bluesky}
                    icon={:bluesky}
                    label="Bluesky"
                    placeholder="Bluesky username"
                  />
                  <.social_input
                    form={fh}
                    field={:github}
                    icon={:github}
                    label="GitHub"
                    placeholder="GitHub username"
                  />
                  <.social_input
                    form={fh}
                    field={:elixirforum}
                    icon={:elixirforum}
                    label="Elixir Forum"
                    placeholder="Elixir Forum username"
                  />
                </div>
              </div>
            <% end) %>

            <div class="flex justify-start pt-6">
              <.button type="submit" variant="primary">Save Changes</.button>
            </div>
          </div>
        <% end %>
      <% else %>
        <div class="rounded-lg bg-amber-50 border border-amber-200 p-4 text-sm text-amber-800">
          There is no profile associated with your organization. To enable the profile, your organization needs to be migrated. Please contact{" "}
          <a href="mailto:support@hex.pm" class="underline hover:text-amber-900">support@hex.pm</a>.
        </div>
      <% end %>
    </div>
    """
  end
end
