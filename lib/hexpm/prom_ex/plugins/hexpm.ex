defmodule Hexpm.PromEx.Plugins.Hexpm do
  @moduledoc """
  PromEx plugin for hex.pm business metrics, counting the domain events
  emitted from the contexts (see `Hexpm.Repository.Releases`,
  `Hexpm.Accounts.Users`, and `Hexpm.TrustedPublishers`).
  """

  use PromEx.Plugin

  @impl true
  def event_metrics(_opts) do
    Event.build(:hexpm_business_event_metrics, [
      counter("hexpm.repository.publish.total",
        event_name: [:hexpm, :repository, :publish],
        description: "Package releases published."
      ),
      counter("hexpm.repository.publish_docs.total",
        event_name: [:hexpm, :repository, :publish_docs],
        description: "Documentation bundles published."
      ),
      counter("hexpm.accounts.user_created.total",
        event_name: [:hexpm, :accounts, :user_created],
        description: "New user accounts created."
      ),
      counter("hexpm.trusted_publishers.mint.success.total",
        event_name: [:hexpm, :trusted_publishers, :mint, :success],
        description: "Trusted publisher OIDC tokens successfully exchanged for Hex tokens.",
        tags: [:provider],
        tag_values: &__MODULE__.mint_success_tags/1
      ),
      counter("hexpm.trusted_publishers.mint.failure.total",
        event_name: [:hexpm, :trusted_publishers, :mint, :failure],
        description: "Trusted publisher mint attempts that failed.",
        tags: [:reason],
        tag_values: &__MODULE__.mint_failure_tags/1
      )
    ])
  end

  @doc false
  def mint_success_tags(metadata) do
    %{provider: stringify(Map.get(metadata, :provider, "unknown"))}
  end

  @doc false
  def mint_failure_tags(metadata) do
    %{reason: stringify(Map.get(metadata, :reason, "unknown"))}
  end

  defp stringify(value) when is_atom(value), do: Atom.to_string(value)
  defp stringify(value) when is_binary(value), do: value
  defp stringify(_value), do: "unknown"
end
