defmodule HexpmWeb.Components.Sponsors do
  use Phoenix.Component

  @doc """
  Renders a sponsor card with logo, description, and external link icon.
  """
  attr :name, :string, required: true
  attr :url, :string, required: true
  attr :logo_src, :string, required: true
  attr :description, :string, required: true
  attr :contribution, :string, required: true

  def sponsor_card(assigns) do
    ~H"""
    <article class="tw:bg-white tw:border tw:border-grey-200 tw:rounded-lg tw:p-6 tw:flex tw:flex-col tw:flex-1">
      <div class="tw:mb-4 tw:flex tw:items-center tw:justify-between">
        <a
          href={@url}
          class="tw:block tw:flex-shrink-0"
          target="_blank"
          rel="noopener noreferrer"
        >
          <img src={@logo_src} alt={"#{@name} logo"} class="tw:h-12 tw:w-auto tw:object-contain" />
        </a>
        <a
          href={@url}
          target="_blank"
          rel="noopener noreferrer"
          class="tw:text-grey-400 hover:tw:text-blue-500 tw:transition-colors tw:ml-4"
          aria-label={"Visit #{@name} website"}
        >
          <svg
            xmlns="http://www.w3.org/2000/svg"
            fill="none"
            viewBox="0 0 24 24"
            stroke-width="1.5"
            stroke="currentColor"
            class="tw:w-5 tw:h-5"
          >
            <path
              stroke-linecap="round"
              stroke-linejoin="round"
              d="M13.5 6H5.25A2.25 2.25 0 003 8.25v10.5A2.25 2.25 0 005.25 21h10.5A2.25 2.25 0 0018 18.75V10.5m-10.5 6L21 3m0 0h-5.25M21 3v5.25"
            />
          </svg>
        </a>
      </div>

      <div class="tw:text-grey-600 tw:text-sm tw:leading-6 tw:space-y-3 tw:flex-1">
        <p>
          {@description}
        </p>
        <p class="tw:font-medium tw:text-grey-900">
          {@contribution}
        </p>
      </div>
    </article>
    """
  end
end
