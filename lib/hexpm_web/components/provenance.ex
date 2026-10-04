defmodule HexpmWeb.Components.Provenance do
  use Phoenix.Component

  alias Hexpm.TrustedPublishers.ClaimsSnapshot

  attr :claims, ClaimsSnapshot, required: true

  def provenance(assigns) do
    ~H"""
    <div class="bg-white dark:bg-grey-800 border border-grey-200 dark:border-grey-700 rounded-lg p-5 flex flex-col gap-4">
      <h3 class="text-grey-700 dark:text-grey-100 text-lg font-semibold">Provenance</h3>
      <div class="flex flex-col gap-1">
        <p class="text-grey-400 dark:text-grey-300 text-[10px] font-medium uppercase tracking-wide">
          Published from
        </p>
        <div class="flex items-center gap-2">
          {HexpmWeb.ViewIcons.icon(:heroicon, "check-badge",
            class: "size-5 text-green-600 dark:text-green-400"
          )}
          <span class="text-grey-700 dark:text-grey-100 font-bold">GitHub Actions</span>
        </div>
        <.provenance_link
          :if={ClaimsSnapshot.run_url(@claims)}
          href={ClaimsSnapshot.run_url(@claims)}
        >
          View build summary
        </.provenance_link>
      </div>
      <dl class="flex flex-col gap-3">
        <.provenance_entry label="Source Commit">
          <.provenance_link href={
            ClaimsSnapshot.commit_url(@claims) || ClaimsSnapshot.repository_url(@claims)
          }>
            github.com/{@claims.repository}{if @claims.sha,
              do: "@#{String.slice(@claims.sha, 0, 7)}"}
          </.provenance_link>
        </.provenance_entry>
        <.provenance_entry :if={ClaimsSnapshot.workflow_path(@claims)} label="Build File">
          <.provenance_link href={ClaimsSnapshot.workflow_url(@claims)}>
            {ClaimsSnapshot.workflow_path(@claims)}
          </.provenance_link>
        </.provenance_entry>
        <.provenance_entry :if={@claims.ref} label={ref_label(@claims)}>
          <.provenance_link href={ClaimsSnapshot.ref_url(@claims)}>
            {ClaimsSnapshot.ref_name(@claims)}
          </.provenance_link>
        </.provenance_entry>
        <.provenance_entry :if={@claims.environment} label="Environment">
          <.provenance_link href={ClaimsSnapshot.environment_url(@claims)}>
            {@claims.environment}
          </.provenance_link>
        </.provenance_entry>
        <.provenance_entry :if={@claims.actor} label="Triggered By">
          <span class="flex flex-wrap gap-1">
            <.provenance_link href={ClaimsSnapshot.actor_url(@claims)}>
              {@claims.actor}
            </.provenance_link>
            <span :if={@claims.event_name} class="text-grey-500 dark:text-grey-300">
              on {@claims.event_name}
            </span>
          </span>
        </.provenance_entry>
      </dl>
    </div>
    """
  end

  attr :label, :string, required: true
  slot :inner_block, required: true

  defp provenance_entry(assigns) do
    ~H"""
    <div class="flex flex-col gap-0.5">
      <dt class="text-grey-400 dark:text-grey-300 text-[10px] font-medium uppercase tracking-wide">
        {@label}
      </dt>
      <dd class="text-grey-700 dark:text-grey-100 text-sm font-medium break-all">
        {render_slot(@inner_block)}
      </dd>
    </div>
    """
  end

  attr :href, :string, default: nil
  slot :inner_block, required: true

  defp provenance_link(%{href: nil} = assigns) do
    ~H"""
    <span>{render_slot(@inner_block)}</span>
    """
  end

  defp provenance_link(assigns) do
    ~H"""
    <a
      href={@href}
      rel="nofollow"
      class="text-sm text-blue-600 dark:text-blue-300 hover:text-blue-700 dark:hover:text-blue-200 underline"
    >
      {render_slot(@inner_block)}
    </a>
    """
  end

  defp ref_label(%ClaimsSnapshot{ref_type: "branch"}), do: "Branch"
  defp ref_label(%ClaimsSnapshot{ref_type: "tag"}), do: "Tag"
  defp ref_label(%ClaimsSnapshot{}), do: "Ref"
end
