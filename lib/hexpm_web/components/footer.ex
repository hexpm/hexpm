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
    <footer class="bg-grey-900 text-grey-200 font-sans">
      <div class="max-w-7xl mx-auto px-4 pt-12 pb-10 flex flex-col gap-10">
        <div class="flex flex-col gap-10 lg:flex-row lg:items-start lg:gap-24 xl:gap-28">
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
    <div class="flex w-full items-start justify-between gap-6 lg:w-auto lg:flex-col lg:items-start lg:justify-start lg:gap-6">
      <div class="flex items-center gap-3">
        <img src={~p"/images/hex-full.svg"} alt="hex logo" class="h-8 w-auto" />
        <span class="text-white text-2xl font-bold tracking-tight">
          Hex
        </span>
      </div>
      <.social_links />
    </div>
    """
  end

  defp social_links(assigns) do
    ~H"""
    <div class="flex gap-3 lg:mt-4">
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
      class="inline-flex h-10 w-10 items-center justify-center rounded-lg bg-grey-800 text-slate-200 hover:bg-grey-700 transition duration-200 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-grey-500"
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
    <div class="flex-1">
      <div class="grid grid-cols-2 gap-y-4 gap-x-12 md:grid-cols-3 lg:gap-x-16 xl:gap-x-24">
        <.footer_link_column>
          <.footer_link href={~p"/about"} label="About" />
          <.footer_link href={~p"/blog"} label="Blog" />
          <.footer_link href={~p"/sponsors"} label="Sponsors" />
          <.footer_link href="https://status.hex.pm" label="Status" external />
        </.footer_link_column>

        <.footer_link_column>
          <.footer_link href={~p"/docs"} label="Documentation" />
          <.footer_link href={~p"/docs/faq"} label="FAQ" />
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
          <.footer_link href="mailto:support@hex.pm" label="Contact Support" />
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
    <div class="flex flex-col gap-3 font-medium leading-4">
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
      class="text-grey-200 hover:text-white transition-colors"
      target={if @external, do: "_blank"}
      rel={if @external, do: "noopener noreferrer"}
    >
      {@label}
    </a>
    """
  end

  defp footer_copyright(assigns) do
    ~H"""
    <div class="bg-grey-800">
      <div class="max-w-7xl mx-auto px-4 py-4 flex flex-col items-center gap-3 text-sm text-grey-200 md:flex-row md:justify-between">
        <p class="text-center leading-[14px] md:text-left">
          Copyright 2015. Six Colors AB.
        </p>
        <p class="text-center leading-[18px] md:text-right">
          Powered by the
          <a href="https://www.erlang.org/" class="underline hover:text-grey-300">Erlang VM</a>
          and the
          <a href="https://elixir-lang.org/" class="underline hover:text-grey-300">
            Elixir Programming Language
          </a>
        </p>
      </div>
    </div>
    """
  end
end
