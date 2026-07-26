defmodule Hexpm.PromEx.Plugins.Hexpm do
  @moduledoc """
  PromEx plugin for hex.pm business metrics, counting the domain events
  emitted from the contexts (see `Hexpm.Repository.Releases` and
  `Hexpm.Accounts.Users`).
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
      )
    ])
  end
end
