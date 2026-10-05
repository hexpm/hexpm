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

  # A publisher that matches every repository of its owner pins the owner id
  # alone.
  @impl true
  def resolve_immutable_ids(%{repository: "", repository_owner: owner}) do
    if valid_owner?(owner), do: fetch_owner_id(owner), else: {:error, :repository_not_found}
  end

  def resolve_immutable_ids(%{repository: repository}) do
    with {:ok, owner, name} <- split_repository(repository) do
      fetch_repository_ids(owner, name)
    end
  end

  # pull_request_target runs with the base repository's permissions, so a
  # workflow that checks out the pull request head would hand a fork's code an
  # OIDC token. workflow_run gets the same permissions when a fork's pull
  # request triggered the run, and no claim says whether it did.
  @impl true
  def validate_claims(%{"event_name" => event})
      when event in ["pull_request_target", "workflow_run"],
      do: {:error, :event_not_allowed}

  def validate_claims(claims) when is_map(claims), do: :ok

  # Keyed on a claim GitHub signed, so a failing repository only throttles
  # itself and never the runners it shares an address with.
  @impl true
  def rate_limit_key(claims) when is_map(claims),
    do: {:github_repository, to_string_or_nil(claims["repository_id"])}

  # The GitHub namespace and environment names are case-insensitive, so owner,
  # repository, and environment are compared case-insensitively, with owner and
  # repository pinned by their immutable ids. The workflow is matched exactly:
  # git paths are case-sensitive, so `Release.yml` must not satisfy a publisher
  # configured for `release.yml`.
  @impl true
  def match?(%TrustedPublisher{} = publisher, claims) when is_map(claims) do
    repository = downcase(claims["repository"])
    owner_id = to_string_or_nil(claims["repository_owner_id"])
    repository_id = to_string_or_nil(claims["repository_id"])
    workflow = workflow_filename(claims)
    environment = claims["environment"] || ""

    repository_matches?(publisher, repository, repository_id) and
      owner_id == publisher.repository_owner_id and
      workflow_matches?(publisher, workflow) and
      environment_matches?(publisher, environment)
  end

  # An organization read publisher with no repository matches every repository
  # of the pinned owner.
  defp repository_matches?(
         %{repository: "", role: "read", organization_id: organization_id},
         repository,
         repository_id
       )
       when not is_nil(organization_id),
       do: is_binary(repository) and is_binary(repository_id)

  defp repository_matches?(publisher, repository, repository_id) do
    repository == downcase(publisher.repository) and
      repository_id_matches?(publisher, repository_id)
  end

  @impl true
  def claims_snapshot(claims) when is_map(claims) do
    claims
    |> Map.take([
      "repository",
      "repository_id",
      "repository_owner",
      "repository_owner_id",
      "workflow_ref",
      "job_workflow_ref",
      "environment",
      "sha",
      "ref",
      "ref_type",
      "run_id",
      "run_number",
      "run_attempt",
      "actor",
      "actor_id",
      "event_name"
    ])
    |> Map.new(fn {key, value} -> {key, to_string_or_nil(value)} end)
  end

  defp repository_id_matches?(%{repository_id: expected}, actual)
       when is_binary(expected) and expected != "" and is_binary(actual),
       do: expected == actual

  defp repository_id_matches?(_publisher, _actual), do: false

  defp workflow_matches?(%{workflow: "", role: "read", organization_id: id}, _actual)
       when not is_nil(id),
       do: true

  defp workflow_matches?(%{workflow: expected}, actual)
       when is_binary(expected) and expected != "" and is_binary(actual),
       do: expected == actual

  defp workflow_matches?(_publisher, _actual), do: false

  defp environment_matches?(%{environment: env}, _token_environment) when env in [nil, ""],
    do: true

  defp environment_matches?(%{environment: expected}, actual),
    do: downcase(expected) == downcase(actual)

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

  # A workflow filename may contain `@` but never `/`, so the ref starts at the
  # first `@refs/`. A ref that isn't under refs/ leaves the path unmatched.
  defp extract_workflow_filename(value, repository)
       when is_binary(value) and is_binary(repository) and repository != "" do
    path =
      value
      |> String.split("@refs/", parts: 2)
      |> List.first()

    prefix = String.downcase(repository) <> "/"

    if String.starts_with?(String.downcase(path), prefix) do
      Path.basename(path)
    else
      nil
    end
  end

  defp extract_workflow_filename(_, _), do: nil

  defp split_repository(repository) when is_binary(repository) do
    case String.split(repository, "/") do
      [owner, name] ->
        if valid_owner?(owner) and valid_repo_name?(name) do
          {:ok, owner, name}
        else
          {:error, :repository_not_found}
        end

      _ ->
        {:error, :repository_not_found}
    end
  end

  defp split_repository(_repository), do: {:error, :repository_not_found}

  # One call covers a repository Hex can see. A private repository answers 404
  # here while its owner's profile stays public, so the fallback resolves the
  # owner id alone and returns no repository id for the caller to supply.
  defp fetch_repository_ids(owner, name) do
    case github_get("/repos/#{URI.encode(owner)}/#{URI.encode(name)}") do
      {:ok, %{"id" => repository_id, "owner" => %{"id" => owner_id}}}
      when is_integer(repository_id) and is_integer(owner_id) ->
        {:ok, %{repository_owner_id: owner_id, repository_id: repository_id}}

      {:ok, _body} ->
        {:error, :invalid_github_response}

      {:error, :not_found} ->
        fetch_owner_id(owner)

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp fetch_owner_id(owner) do
    case github_get("/users/#{URI.encode(owner)}") do
      {:ok, %{"id" => owner_id}} when is_integer(owner_id) ->
        {:ok, %{repository_owner_id: owner_id, repository_id: nil}}

      {:ok, _body} ->
        {:error, :invalid_github_response}

      {:error, :not_found} ->
        {:error, :repository_not_found}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp valid_owner?(owner), do: Regex.match?(~r/\A[A-Za-z0-9._-]+\z/, owner)

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

    config = Application.get_env(:ueberauth, Ueberauth.Strategy.Github.OAuth, [])

    case {config[:client_id], config[:client_secret]} do
      {id, secret} when is_binary(id) and id != "" and is_binary(secret) and secret != "" ->
        [{"authorization", "Basic " <> Base.encode64(id <> ":" <> secret)} | headers]

      _ ->
        headers
    end
  end

  defp to_string_or_nil(nil), do: nil
  defp to_string_or_nil(value), do: to_string(value)

  defp downcase(nil), do: nil
  defp downcase(value) when is_binary(value), do: String.downcase(value)
  defp downcase(_), do: nil
end
