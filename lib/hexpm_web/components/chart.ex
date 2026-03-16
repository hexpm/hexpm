defmodule HexpmWeb.Components.Chart do
  use Phoenix.Component

  alias HexpmWeb.ViewHelpers

  attr :id, :string, required: true
  attr :graph_points, :string, required: true
  attr :graph_fill, :string, required: true
  attr :y_axis_labels, :list, required: true
  attr :aria_label, :string, default: "Downloads over the last 30 days"

  def downloads_chart(assigns) do
    ~H"""
    <svg
      viewBox="0 -3 880 213"
      class="w-full h-auto"
      role="img"
      aria-label={@aria_label}
    >
      <defs>
        <linearGradient
          id={"#{@id}-line"}
          gradientUnits="userSpaceOnUse"
          x1="0"
          y1="0"
          x2="800"
          y2="0"
        >
          <stop offset="0%" stop-color="#7c3aed" />
          <stop offset="100%" stop-color="#a855f7" />
        </linearGradient>
        <linearGradient
          id={"#{@id}-fill"}
          gradientUnits="userSpaceOnUse"
          x1="0"
          y1="0"
          x2="0"
          y2="200"
        >
          <stop offset="0%" stop-color="#7c3aed" stop-opacity="0.12" />
          <stop offset="100%" stop-color="#7c3aed" stop-opacity="0.01" />
        </linearGradient>
      </defs>
      <%!-- Y-axis labels --%>
      <%= for {label, y} <- @y_axis_labels do %>
        <text
          x="72"
          y={y}
          text-anchor="end"
          fill="#9ca3af"
          font-size="22"
          font-family="ui-monospace, SFMono-Regular, monospace"
        >
          {ViewHelpers.human_number_space(label)}
        </text>
      <% end %>
      <%!-- Chart area --%>
      <g transform="translate(80, 0)">
        <%!-- Horizontal grid lines --%>
        <%= for y <- [38, 78, 118, 158, 198] do %>
          <line
            x1="0"
            y1={y}
            x2="800"
            y2={y}
            stroke="#f3f4f6"
            stroke-width="1"
          />
        <% end %>
        <%!-- Fill area --%>
        <path
          fill={"url(##{@id}-fill)"}
          d={@graph_fill}
        />
        <%!-- Line --%>
        <path
          fill="none"
          stroke={"url(##{@id}-line)"}
          stroke-width="2.5"
          stroke-linecap="round"
          stroke-linejoin="round"
          d={@graph_points}
        />
      </g>
    </svg>
    """
  end
end
