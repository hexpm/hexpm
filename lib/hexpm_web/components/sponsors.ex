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
    <article class="bg-white border border-grey-200 rounded-lg p-6 flex flex-col flex-1">
      <div class="mb-4 flex items-center justify-between">
        <a
          href={@url}
          class="block flex-shrink-0"
          target="_blank"
          rel="noopener noreferrer"
        >
          <img src={@logo_src} alt={"#{@name} logo"} class="h-12 w-auto object-contain" />
        </a>
        <a
          href={@url}
          target="_blank"
          rel="noopener noreferrer"
          class="text-grey-400 hover:text-blue-500 transition-colors ml-4"
          aria-label={"Visit #{@name} website"}
        >
          <svg
            xmlns="http://www.w3.org/2000/svg"
            fill="none"
            viewBox="0 0 24 24"
            stroke-width="1.5"
            stroke="currentColor"
            class="w-5 h-5"
          >
            <path
              stroke-linecap="round"
              stroke-linejoin="round"
              d="M13.5 6H5.25A2.25 2.25 0 003 8.25v10.5A2.25 2.25 0 005.25 21h10.5A2.25 2.25 0 0018 18.75V10.5m-10.5 6L21 3m0 0h-5.25M21 3v5.25"
            />
          </svg>
        </a>
      </div>

      <div class="text-grey-600 text-sm leading-6 space-y-3 flex-1">
        <p>
          {@description}
        </p>
        <p class="font-medium text-grey-900">
          {@contribution}
        </p>
      </div>
    </article>
    """
  end
end
