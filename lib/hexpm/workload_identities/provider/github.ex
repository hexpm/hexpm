defmodule Hexpm.WorkloadIdentities.Provider.GitHub do
  @moduledoc """
  GitHub Actions workload identity provider.
  """

  @behaviour Hexpm.WorkloadIdentities.Provider

  alias Hexpm.WorkloadIdentities.WorkloadIdentity

  @issuer "https://token.actions.githubusercontent.com"
  @github_api "https://api.github.com"

  @impl true
  def name, do: "github"

  @impl true
  def issuer, do: @issuer

  # The owner's ID comes from the repositories Hex can see, then from the ID
  # already pinned, then from the owner's profile. The profile is also all a
  # workload identity that matches every repository of its owner pins.
  @impl true
  def resolve_immutable_ids(%{repository_owner: owner, repositories: names} = attrs) do
    with true <- valid_owner?(owner) || {:error, :repository_not_found},
         {:ok, repositories} <- fetch_repositories(owner, names),
         {:ok, owner_id} <- owner_id(owner, repositories, Map.get(attrs, :repository_owner_id)) do
      {:ok,
       %{
         repository_owner_id: owner_id,
         repositories:
           Map.new(repositories, fn {name, repository} ->
             {name, Map.delete(repository, :owner_id)}
           end)
       }}
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
  # git paths are case-sensitive, so `Release.yml` must not satisfy a workload identity
  # configured for `release.yml`.
  @impl true
  def match?(%WorkloadIdentity{} = workload_identity, claims) when is_map(claims) do
    repository = downcase(claims["repository"])
    owner_id = to_string_or_nil(claims["repository_owner_id"])
    repository_id = to_string_or_nil(claims["repository_id"])
    workflow = workflow_filename(claims)
    environment = claims["environment"] || ""
    visibility = claims["repository_visibility"]

    repository_matches?(workload_identity, repository, repository_id) and
      owner_id == workload_identity.repository_owner_id and
      workflow_matches?(workload_identity, workflow) and
      environment_matches?(workload_identity, environment, visibility)
  end

  # An organization read workload identity with no repositories matches every
  # repository of the pinned owner. Any other matches one of its repositories
  # by name and pinned ID.
  defp repository_matches?(
         %{repositories: [], role: "read", organization_id: organization_id},
         repository,
         repository_id
       )
       when not is_nil(organization_id),
       do: is_binary(repository) and is_binary(repository_id)

  defp repository_matches?(%{repositories: repositories}, repository, repository_id)
       when is_binary(repository) and is_binary(repository_id) do
    Enum.any?(repositories, fn trusted ->
      is_binary(trusted.id) and trusted.id != "" and trusted.id == repository_id and
        downcase(trusted.name) == repository
    end)
  end

  defp repository_matches?(_workload_identity, _repository, _repository_id), do: false

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

  defp workflow_matches?(%{workflow: "", role: "read", organization_id: id}, _actual)
       when not is_nil(id),
       do: true

  defp workflow_matches?(%{workflow: expected}, actual)
       when is_binary(expected) and expected != "" and is_binary(actual),
       do: expected == actual

  defp workflow_matches?(_workload_identity, _actual), do: false

  # A workload identity that publishes from a public repository must name an
  # environment, see `WorkloadIdentity.validate_public_environment/2`. One added
  # while its repository was private may have none, so it stops matching once
  # the repository is public.
  defp environment_matches?(%{role: "write", environment: env}, _actual, "public")
       when env in [nil, ""],
       do: false

  defp environment_matches?(%{environment: env}, _actual, _visibility) when env in [nil, ""],
    do: true

  defp environment_matches?(%{environment: expected}, actual, _visibility),
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

  # One call per repository, a few at a time. A private repository answers 404
  # while its owner's profile stays public, so it resolves without an ID, which
  # the admin supplies.
  defp fetch_repositories(owner, names) do
    names
    |> Task.async_stream(&fetch_repository(owner, &1),
      max_concurrency: 8,
      timeout: lookup_timeout(),
      on_timeout: :kill_task
    )
    |> Enum.reduce_while({:ok, []}, fn
      {:ok, {:ok, entry}}, {:ok, entries} -> {:cont, {:ok, [entry | entries]}}
      {:ok, {:error, reason}}, _acc -> {:halt, {:error, reason}}
      {:exit, _reason}, _acc -> {:halt, {:error, :timeout}}
    end)
    |> case do
      {:ok, entries} -> {:ok, Enum.reverse(entries)}
      error -> error
    end
  end

  defp fetch_repository(owner, name) do
    with {:ok, short_name} <- short_name(owner, name) do
      case github_get("/repos/#{URI.encode(owner)}/#{URI.encode(short_name)}") do
        {:ok, %{"id" => repository_id, "owner" => %{"id" => owner_id}} = body}
        when is_integer(repository_id) and is_integer(owner_id) ->
          public = body["visibility"] == "public"
          {:ok, {name, %{id: repository_id, owner_id: owner_id, public: public}}}

        {:ok, _body} ->
          {:error, :invalid_github_response}

        {:error, :not_found} ->
          {:ok, {name, %{id: nil, owner_id: nil, public: false}}}

        {:error, :moved} ->
          {:ok, {name, %{id: nil, owner_id: nil, public: false, moved: true}}}

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  defp lookup_timeout,
    do: Application.fetch_env!(:hexpm, :workload_identity)[:github_lookup_timeout]

  defp short_name(owner, name) do
    case String.split(name, "/") do
      [^owner, short_name] ->
        if valid_repo_name?(short_name),
          do: {:ok, short_name},
          else: {:error, :repository_not_found}

      _ ->
        {:error, :repository_not_found}
    end
  end

  # Every repository Hex can see under the owner's name reports the owner's
  # ID, so differing IDs mean GitHub answered for something else.
  defp owner_id(owner, repositories, pinned_owner_id) do
    owner_ids =
      repositories
      |> Enum.map(fn {_name, repository} -> repository.owner_id end)
      |> Enum.reject(&is_nil/1)
      |> Enum.uniq()

    case {owner_ids, pinned_owner_id} do
      {[], nil} -> fetch_owner_id(owner)
      {[], pinned_owner_id} -> {:ok, pinned_owner_id}
      {[owner_id], _pinned_owner_id} -> {:ok, owner_id}
      {_owner_ids, _pinned_owner_id} -> {:error, :repository_not_found}
    end
  end

  defp fetch_owner_id(owner) do
    case github_get("/users/#{URI.encode(owner)}") do
      {:ok, %{"id" => owner_id}} when is_integer(owner_id) ->
        {:ok, owner_id}

      {:ok, _body} ->
        {:error, :invalid_github_response}

      {:error, :not_found} ->
        {:error, :repository_not_found}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp valid_owner?(owner) when is_binary(owner), do: Regex.match?(~r/\A[A-Za-z0-9._-]+\z/, owner)
  defp valid_owner?(_owner), do: false

  defp valid_repo_name?(name), do: Regex.match?(~r/\A[A-Za-z0-9._-]+\z/, name)

  defp github_get(path) do
    url = @github_api <> path
    headers = github_headers()

    case Hexpm.HTTP.impl().get(url, headers, decode_body: true, receive_timeout: 5_000) do
      {:ok, 200, _headers, body} when is_map(body) -> {:ok, body}
      {:ok, 404, _headers, _body} -> {:error, :not_found}
      # A renamed or transferred repository redirects to its new location.
      {:ok, status, _headers, _body} when status in [301, 302, 307, 308] -> {:error, :moved}
      {:ok, status, _headers, _body} -> {:error, {:http_status, status}}
      {:error, reason} -> {:error, reason}
    end
  end

  defp github_headers do
    headers = [
      {"accept", "application/vnd.github+json"},
      {"user-agent", "hexpm-workload-identities"}
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
