defmodule HexpmWeb.API.TrustedPublisherView do
  use HexpmWeb, :view

  def render("index." <> _, %{trusted_publishers: trusted_publishers}) do
    Enum.map(trusted_publishers, &trusted_publisher_json/1)
  end

  def render("show." <> _, %{trusted_publisher: trusted_publisher}) do
    trusted_publisher_json(trusted_publisher)
  end

  defp trusted_publisher_json(trusted_publisher) do
    %{
      id: trusted_publisher.id,
      provider: trusted_publisher.provider,
      issuer: trusted_publisher.issuer,
      repository_owner: trusted_publisher.repository_owner,
      github_repository: trusted_publisher.repository,
      workflow: trusted_publisher.workflow,
      environment: empty_to_nil(trusted_publisher.environment),
      inserted_at: trusted_publisher.inserted_at,
      updated_at: trusted_publisher.updated_at
    }
  end

  defp empty_to_nil(""), do: nil
  defp empty_to_nil(value), do: value
end
