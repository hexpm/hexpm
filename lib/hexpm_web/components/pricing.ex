defmodule HexpmWeb.Components.Pricing do
  @moduledoc """
  Components for the pricing page.
  """
  use Phoenix.Component
  alias Phoenix.LiveView.JS
  import HexpmWeb.Components.Buttons
  import HexpmWeb.ViewIcons, only: [icon: 3]

  use Phoenix.VerifiedRoutes,
    endpoint: HexpmWeb.Endpoint,
    router: HexpmWeb.Router,
    statics: HexpmWeb.static_paths()

  @doc """
  Renders a pricing card with icon, price, features, and CTA button.

  ## Examples

      <.pricing_card
        icon_src={~p"/images/pricing/open-source-icon.svg"}
        icon_bg="blue"
        price_monthly={0}
        price_yearly={0}
        title="Open Source"
        description="For Public Open Source Packages"
        cta_text="Get Started for FREE"
        cta_href={~p"/signup"}
      >
        <:feature>Unlimited number of public packages</:feature>
        <:feature>Public Packages Documentation</:feature>
        <:feature>Multiple Package Owners</:feature>
      </.pricing_card>
  """
  attr :cta_href, :string, required: true
  attr :cta_text, :string, required: true
  attr :description, :string, required: true
  attr :icon_bg, :string, required: true, values: ["blue", "green", "purple"]
  attr :icon_src, :string, required: true
  attr :price_monthly, :integer, default: nil
  attr :price_yearly, :integer, default: nil
  attr :price_text, :string, default: nil
  attr :title, :string, required: true
  slot :feature, required: true

  def pricing_card(assigns) do
    ~H"""
    <div class="tw:bg-white tw:border tw:border-grey-200 tw:rounded-lg tw:p-6 tw:flex tw:flex-col">
      <%!-- Icon --%>
      <div class="tw:mb-6">
        <div class={[
          "tw:size-15 tw:rounded-full tw:flex tw:items-center tw:justify-center",
          icon_bg_class(@icon_bg)
        ]}>
          <img src={@icon_src} alt={@title} class="tw:size-8" />
        </div>
      </div>

      <%!-- Price --%>
      <div class="tw:mb-6">
        <%= if @price_text do %>
          <div class="tw:flex tw:items-baseline tw:gap-2 tw:mb-4">
            <span class="tw:text-grey-900 tw:text-5xl tw:font-bold">{@price_text}</span>
          </div>
        <% else %>
          <%!-- Monthly Price --%>
          <div class="price-display monthly-active tw:flex tw:items-baseline tw:gap-2 tw:mb-4">
            <span class="tw:text-grey-900 tw:text-5xl tw:font-bold">
              ${@price_monthly}
            </span>
            <span class="tw:text-grey-500">/mo</span>
          </div>
          <%!-- Yearly Price --%>
          <div class="price-display tw:hidden tw:items-baseline tw:gap-2 tw:mb-4">
            <span class="tw:text-grey-900 tw:text-5xl tw:font-bold">
              ${@price_yearly}
            </span>
            <span class="tw:text-grey-500">/yr</span>
          </div>
        <% end %>
      </div>

      <%!-- Title & Description --%>
      <div class="tw:mb-6">
        <h3 class="tw:text-grey-900 tw:text-2xl tw:font-semibold tw:mb-2">
          {@title}
        </h3>
        <p class="tw:text-grey-600">
          {@description}
        </p>
      </div>

      <%!-- Features --%>
      <ul class="tw:space-y-3 tw:mb-8 tw:flex-1">
        <li :for={feature <- @feature} class="tw:flex tw:gap-2 tw:items-center">
          {icon(:heroicon, "check-circle", class: "tw:size-4.5 tw:text-blue-500 tw:shrink-0")}
          <span class="tw:text-grey-900">{render_slot(feature)}</span>
        </li>
      </ul>

      <%!-- CTA --%>
      <.button_link href={@cta_href} variant="blue" size="lg" full_width={true}>
        {@cta_text}
      </.button_link>
    </div>
    """
  end

  defp icon_bg_class("blue"), do: "tw:bg-blue-100"
  defp icon_bg_class("green"), do: "tw:bg-green-100"
  defp icon_bg_class("purple"), do: "tw:bg-primary-100"

  @doc """
  Renders a billing period toggle switch (Monthly/Yearly) using client-side JS.

  ## Examples

      <.billing_toggle />
  """
  def billing_toggle(assigns) do
    ~H"""
    <div class="tw:flex tw:items-center tw:justify-center tw:gap-3 tw:mb-12">
      <span class="tw:text-grey-900 tw:text-sm tw:font-medium">Monthly</span>
      <button
        type="button"
        phx-click={toggle_billing()}
        class="tw:relative tw:w-15 tw:h-8 tw:bg-grey-200 tw:rounded-full tw:transition-colors tw:cursor-pointer"
      >
        <div
          id="billing-toggle-indicator"
          class="tw:absolute tw:left-1.5 tw:top-1.5 tw:size-5 tw:bg-blue-500 tw:rounded-full tw:shadow-lg tw:transition-transform tw:duration-200"
        >
        </div>
      </button>
      <span class="tw:text-grey-900 tw:text-sm tw:font-medium">Yearly</span>
    </div>
    """
  end

  defp toggle_billing do
    JS.toggle_class("tw:translate-x-[28px]", to: "#billing-toggle-indicator")
    |> JS.toggle_class("tw:hidden", to: ".price-display")
    |> JS.toggle_class("tw:flex", to: ".price-display")
  end

  @doc """
  Renders an FAQ accordion item.

  ## Examples

      <.faq_item>
        <:question>What is your refund policy?</:question>
        <:answer>
          We offer a 30-day money-back guarantee...
        </:answer>
      </.faq_item>
  """
  slot :answer, required: true
  slot :question, required: true

  def faq_item(assigns) do
    ~H"""
    <details class="tw:group tw:py-6">
      <summary class="tw:flex tw:justify-between tw:items-center tw:cursor-pointer tw:list-none">
        <span class="tw:text-grey-900 tw:text-xl tw:font-medium">
          {render_slot(@question)}
        </span>
        <svg
          class="tw:size-6 tw:text-grey-900 tw:transition-transform group-open:tw:rotate-45"
          fill="none"
          viewBox="0 0 24 24"
          stroke="currentColor"
        >
          <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 4v16m8-8H4" />
        </svg>
      </summary>
      <div class="tw:mt-4 tw:text-grey-600">
        {render_slot(@answer)}
      </div>
    </details>
    """
  end
end
