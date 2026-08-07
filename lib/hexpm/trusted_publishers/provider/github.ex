defmodule Hexpm.TrustedPublishers.Provider.GitHub do
  @moduledoc """
  GitHub Actions trusted publisher provider.
  """

  @behaviour Hexpm.TrustedPublishers.Provider

  alias Hexpm.TrustedPublishers.TrustedPublisher

  @issuer "https://token.actions.githubusercontent.com"
  @github_api "https://api.github.com"

  @impl true
  def name, do: "github"

  @impl true
  def issuer, do: @issuer

  @impl true
  def required_claims, do: [:repository_owner, :repository, :workflow]

  @impl true
  def supported_claims, do: [:repository_owner, :repository, :workflow, :environment]

  @impl true
  def resolve_immutable_ids(%{repository_owner: owner, repository: repository}) do
    with {:ok, owner_id} <- fetch_user_id(owner),
         {:ok, repository_id} <- fetch_repository_id(repository, owner) do
      {:ok, %{repository_owner_id: owner_id, repository_id: repository_id}}
    end
  end

  @impl true
  def match?(%TrustedPublisher{} = publisher, claims) when is_map(claims) do
    repository = downcase(claims["repository"])
    owner_id = to_string_or_nil(claims["repository_owner_id"])
    repository_id = to_string_or_nil(claims["repository_id"])
    workflow = workflow_filename(claims)
    environment = downcase(claims["environment"] || "")

    repository == downcase(publisher.repository) and
      owner_id == publisher.repository_owner_id and
      repository_id_matches?(publisher, repository_id) and
      downcase(workflow) == downcase(publisher.workflow) and
      environment_matches?(publisher, environment)
  end

  defp repository_id_matches?(%{repository_id: nil}, _token_repository_id), do: true

  defp repository_id_matches?(%{repository_id: expected}, actual),
    do: expected == actual

  defp environment_matches?(%{environment: ""}, _token_environment), do: true

  defp environment_matches?(%{environment: expected}, actual),
    do: downcase(expected) == actual

  # Prefer workflow_ref (calling workflow, always in the trusted repo) over
  # job_workflow_ref (may point at a reusable workflow in another repository).
  # Require the ref path to be prefixed by the token's repository claim so a
  # reusable workflow basename alone cannot satisfy the match.
  defp workflow_filename(claims) do
    repository = claims["repository"]

    [
      claims["workflow_ref"],
      claims["job_workflow_ref"]
    ]
    |> Enum.find_value(&extract_workflow_filename(&1, repository))
  end

  defp extract_workflow_filename(nil, _repository), do: nil

  defp extract_workflow_filename(value, repository)
       when is_binary(value) and is_binary(repository) and repository != "" do
    path =
      value
      |> String.split("@", parts: 2)
      |> List.first()

    prefix = String.downcase(repository) <> "/"

    if String.starts_with?(String.downcase(path), prefix) do
      Path.basename(path)
    else
      nil
    end
  end

  defp extract_workflow_filename(_, _), do: nil

  defp fetch_user_id(owner) do
    case github_get("/users/#{URI.encode(owner)}") do
      {:ok, %{"id" => id}} when is_integer(id) -> {:ok, id}
      {:ok, _} -> {:error, :repository_owner_not_found}
      {:error, :not_found} -> {:error, :repository_owner_not_found}
      {:error, reason} -> {:error, reason}
    end
  end

  defp fetch_repository_id(repository, owner) do
    full_name =
      if String.contains?(repository, "/") do
        repository
      else
        "#{owner}/#{repository}"
      end

    case String.split(full_name, "/") do
      [owner_part, name] ->
        if valid_repo_name?(name) do
          path = "/repos/#{URI.encode(owner_part)}/#{URI.encode(name)}"

          case github_get(path) do
            {:ok, %{"id" => id}} when is_integer(id) -> {:ok, id}
            {:ok, _} -> {:error, :repository_not_found}
            {:error, :not_found} -> {:error, :repository_not_found}
            {:error, reason} -> {:error, reason}
          end
        else
          {:error, :repository_not_found}
        end

      _ ->
        {:error, :repository_not_found}
    end
  end

  defp valid_repo_name?(name), do: Regex.match?(~r/\A[A-Za-z0-9._-]+\z/, name)

  defp github_get(path) do
    url = @github_api <> path
    headers = github_headers()

    case Hexpm.HTTP.impl().get(url, headers, decode_body: true, receive_timeout: 5_000) do
      {:ok, 200, _headers, body} when is_map(body) -> {:ok, body}
      {:ok, 404, _headers, _body} -> {:error, :not_found}
      {:ok, status, _headers, _body} -> {:error, {:http_status, status}}
      {:error, reason} -> {:error, reason}
    end
  end

  defp github_headers do
    headers = [
      {"accept", "application/vnd.github+json"},
      {"user-agent", "hexpm-trusted-publishers"}
    ]

    case github_token() do
      token when is_binary(token) and token != "" ->
        [{"authorization", "Bearer #{token}"} | headers]

      _ ->
        headers
    end
  end

  defp github_token do
    Application.get_env(:hexpm, :trusted_publisher_github_token) ||
      Application.get_env(:hexpm, :hexdocs_github_token)
  end

  defp to_string_or_nil(nil), do: nil
  defp to_string_or_nil(value), do: to_string(value)

  defp downcase(nil), do: nil
  defp downcase(value) when is_binary(value), do: String.downcase(value)
  defp downcase(_), do: nil
end
