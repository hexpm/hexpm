defmodule HexpmWeb.Components.Footer do
  @moduledoc """
  Footer component for the site.
  """
  use Phoenix.Component

  import HexpmWeb.Components.Icons

  use Phoenix.VerifiedRoutes,
    endpoint: HexpmWeb.Endpoint,
    router: HexpmWeb.Router,
    statics: HexpmWeb.static_paths()

  @doc """
  Renders the main footer.
  """
  def footer(assigns) do
    ~H"""
    <footer class="tw:bg-grey-900 tw:text-grey-200 tw:font-sans">
      <div class="tw:max-w-7xl tw:mx-auto tw:px-4 tw:pt-12 tw:pb-10 tw:flex tw:flex-col tw:gap-10">
        <div class="tw:flex tw:flex-col tw:gap-10 tw:lg:flex-row tw:lg:items-start tw:lg:gap-24 tw:xl:gap-28">
          <.footer_branding />
          <.footer_links />
        </div>
      </div>
      <.footer_copyright />
    </footer>
    """
  end

  defp footer_branding(assigns) do
    ~H"""
    <div class="tw:flex tw:w-full tw:items-start tw:justify-between tw:gap-6 tw:lg:w-auto tw:lg:flex-col tw:lg:items-start tw:lg:justify-start tw:lg:gap-6">
      <div class="tw:flex tw:items-center tw:gap-3">
        <img src={~p"/images/hex-full.svg"} alt="hex logo" class="tw:h-8 tw:w-auto" />
        <span class="tw:text-white tw:text-2xl tw:font-bold tw:tracking-tight">
          Hex
        </span>
      </div>
      <.social_links />
    </div>
    """
  end

  defp social_links(assigns) do
    ~H"""
    <div class="tw:flex tw:gap-3 tw:lg:mt-4">
      <.social_link
        href="https://github.com/hexpm"
        label="GitHub"
        icon={:github}
      />
      <.social_link
        href="https://twitter.com/hexpm"
        label="Twitter"
        icon={:twitter}
      />
    </div>
    """
  end

  attr :href, :string, required: true
  attr :icon, :atom, required: true
  attr :label, :string, required: true

  defp social_link(assigns) do
    ~H"""
    <a
      href={@href}
      class="tw:inline-flex tw:h-10 tw:w-10 tw:items-center tw:justify-center tw:rounded-lg tw:bg-grey-800 tw:text-slate-200 tw:hover:bg-grey-700 tw:transition tw:duration-200 tw:focus-visible:outline-2 tw:focus-visible:outline-offset-2 tw:focus-visible:outline-grey-500"
      target="_blank"
      rel="noopener noreferrer"
      aria-label={@label}
    >
      <.social_icon icon={@icon} />
    </a>
    """
  end

  defp footer_links(assigns) do
    ~H"""
    <div class="tw:flex-1">
      <div class="tw:grid tw:grid-cols-2 tw:gap-y-4 tw:gap-x-12 tw:md:grid-cols-3 tw:lg:gap-x-16 tw:xl:gap-x-24">
        <.footer_link_column>
          <.footer_link href={~p"/about"} label="About" />
          <.footer_link href={~p"/blog"} label="Blog" />
          <.footer_link href={~p"/sponsors"} label="Sponsors" />
          <.footer_link href="https://status.hex.pm" label="Status" external />
        </.footer_link_column>

        <.footer_link_column>
          <.footer_link href={~p"/docs"} label="Documentation" />
          <.footer_link
            href="https://github.com/hexpm/specifications"
            label="Specifications"
            external
          />
          <.footer_link
            href="https://github.com/hexpm/hex/issues"
            label="Report Client Issue"
            external
          />
          <.footer_link
            href="https://github.com/hexpm/hexpm/issues"
            label="Report General Issue"
            external
          />
          <.footer_link href="mailto:security@hex.pm" label="Report Security Issue" />
          <.footer_link href="mailto:support@hex.pm" label="Contact Issue" />
        </.footer_link_column>

        <.footer_link_column>
          <.footer_link href={~p"/policies/codeofconduct"} label="Code of Conduct" />
          <.footer_link href={~p"/policies/termsofservice"} label="Terms of Service" />
          <.footer_link href={~p"/policies/privacy"} label="Privacy Policy" />
          <.footer_link href={~p"/policies/copyright"} label="Copyright Policy" />
          <.footer_link href={~p"/policies/dispute"} label="Dispute Policy" />
        </.footer_link_column>
      </div>
    </div>
    """
  end

  slot :inner_block, required: true

  defp footer_link_column(assigns) do
    ~H"""
    <div class="tw:flex tw:flex-col tw:gap-3 tw:font-medium tw:leading-4">
      {render_slot(@inner_block)}
    </div>
    """
  end

  attr :external, :boolean, default: false
  attr :href, :string, required: true
  attr :label, :string, required: true

  defp footer_link(assigns) do
    ~H"""
    <a
      href={@href}
      class="tw:hover:text-white tw:transition-colors"
      target={if @external, do: "_blank"}
      rel={if @external, do: "noopener noreferrer"}
    >
      {@label}
    </a>
    """
  end

  defp footer_copyright(assigns) do
    ~H"""
    <div class="tw:bg-grey-800">
      <div class="tw:max-w-7xl tw:mx-auto tw:px-4 tw:py-4 tw:flex tw:flex-col tw:items-center tw:gap-3 tw:text-sm tw:text-grey-200 tw:md:flex-row tw:md:justify-between">
        <p class="tw:text-center tw:leading-[14px] tw:md:text-left">
          Copyright 2025. Six Colors AB.
        </p>
        <p class="tw:text-center tw:leading-[18px] tw:md:text-right">
          Powered by the Erlang VM and the Elixir Programming Language
        </p>
      </div>
    </div>
    """
  end
end
