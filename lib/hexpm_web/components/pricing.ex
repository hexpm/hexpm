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
    <div class="bg-white border border-grey-200 rounded-lg p-6 flex flex-col">
      <%!-- Icon --%>
      <div class="mb-6">
        <div class={[
          "size-15 rounded-full flex items-center justify-center",
          icon_bg_class(@icon_bg)
        ]}>
          <img src={@icon_src} alt={@title} class="size-8" />
        </div>
      </div>

      <%!-- Price --%>
      <div class="mb-6">
        <%= if @price_text do %>
          <div class="flex items-baseline gap-2 mb-4">
            <span class="text-grey-900 text-5xl font-bold">{@price_text}</span>
          </div>
        <% else %>
          <%!-- Monthly Price --%>
          <div class="price-display monthly-active flex items-baseline gap-2 mb-4">
            <span class="text-grey-900 text-5xl font-bold">
              ${@price_monthly}
            </span>
            <span class="text-grey-500">/mo</span>
          </div>
          <%!-- Yearly Price --%>
          <div class="price-display hidden items-baseline gap-2 mb-4">
            <span class="text-grey-900 text-5xl font-bold">
              ${@price_yearly}
            </span>
            <span class="text-grey-500">/yr</span>
          </div>
        <% end %>
      </div>

      <%!-- Title & Description --%>
      <div class="mb-6">
        <h3 class="text-grey-900 text-2xl font-semibold mb-2">
          {@title}
        </h3>
        <p class="text-grey-600">
          {@description}
        </p>
      </div>

      <%!-- Features --%>
      <ul class="space-y-3 mb-8 flex-1">
        <li :for={feature <- @feature} class="flex gap-2 items-center">
          {icon(:heroicon, "check-circle", class: "size-4.5 text-blue-500 shrink-0")}
          <span class="text-grey-900">{render_slot(feature)}</span>
        </li>
      </ul>

      <%!-- CTA --%>
      <.button_link href={@cta_href} variant="blue" size="lg" full_width={true}>
        {@cta_text}
      </.button_link>
    </div>
    """
  end

  defp icon_bg_class("blue"), do: "bg-blue-100"
  defp icon_bg_class("green"), do: "bg-green-100"
  defp icon_bg_class("purple"), do: "bg-primary-100"

  @doc """
  Renders a billing period toggle switch (Monthly/Yearly) using client-side JS.

  ## Examples

      <.billing_toggle />
  """
  def billing_toggle(assigns) do
    ~H"""
    <div class="flex items-center justify-center gap-3 mb-12">
      <span class="text-grey-900 text-sm font-medium">Monthly</span>
      <button
        type="button"
        phx-click={toggle_billing()}
        class="relative w-15 h-8 bg-grey-200 rounded-full transition-colors cursor-pointer"
      >
        <div
          id="billing-toggle-indicator"
          class="absolute left-1.5 top-1.5 size-5 bg-blue-500 rounded-full shadow-lg transition-transform duration-200"
        >
        </div>
      </button>
      <span class="text-grey-900 text-sm font-medium">Yearly</span>
    </div>
    """
  end

  defp toggle_billing do
    JS.toggle_class("translate-x-[28px]", to: "#billing-toggle-indicator")
    |> JS.toggle_class("hidden", to: ".price-display")
    |> JS.toggle_class("flex", to: ".price-display")
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
    <details class="group py-6">
      <summary class="flex justify-between items-center cursor-pointer list-none">
        <span class="text-grey-900 text-xl font-medium">
          {render_slot(@question)}
        </span>
        <svg
          class="size-6 text-grey-900 transition-transform group-open:rotate-45"
          fill="none"
          viewBox="0 0 24 24"
          stroke="currentColor"
        >
          <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 4v16m8-8H4" />
        </svg>
      </summary>
      <div class="mt-4 text-grey-600">
        {render_slot(@answer)}
      </div>
    </details>
    """
  end
end
