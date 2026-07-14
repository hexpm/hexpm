defmodule Hexpm.Security.Updater do
  @moduledoc false

  use Oban.Worker,
    queue: :periodic,
    max_attempts: 5,
    unique: [
      period: :infinity,
      states: :incomplete
    ]

  require Logger

  alias Hexpm.Repository.Packages
  alias Hexpm.Security.Advisories

  @advisory_download_url "https://osv-vulnerabilities.storage.googleapis.com/Hex/all.zip"
  @http_receive_timeout 60_000
  @reference_url_schemes ~w(http https)
  @reference_url_max_length 2000

  @impl Oban.Worker
  def timeout(_job), do: 300_000

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{}}) do
    case Hexpm.HTTP.impl().get(@advisory_download_url, [], receive_timeout: @http_receive_timeout) do
      {:ok, 200, _headers, archive} -> unzip_and_process(archive)
      {:ok, status, _headers, _body} -> {:error, {:unexpected_status, status}}
      {:error, reason} -> {:error, {:request_failed, reason}}
    end
  end

  defp unzip_and_process(archive) do
    case :zip.unzip(archive, [:memory]) do
      {:ok, files} -> process_advisories(files)
      {:error, reason} -> {:error, {:invalid_archive, reason}}
    end
  end

  @doc """
  Parses the OSV advisory archive into normalized advisory records and
  upserts them. Public so it can be exercised by tests with a fixture.
  """
  def process_advisories(body) do
    records =
      body
      |> Enum.map(fn {_filename, content} -> Jason.decode!(content) end)
      |> Enum.map(&parse_advisory/1)
      |> Enum.reject(&is_nil/1)

    affected_package_names =
      records
      |> Enum.flat_map(fn %{affected: affected} -> Enum.map(affected, & &1.package) end)
      |> Enum.uniq()

    package_ids = Packages.resolve_hexpm_package_ids(affected_package_names)

    case Advisories.upsert(records, package_ids) do
      {:ok, _changes} ->
        :ok

      {:error, step, value, _changes} ->
        Logger.error("Advisory upsert failed at #{inspect(step)}: #{inspect(value)}")
        {:error, {step, value}}
    end
  end

  defp parse_advisory(advisory) do
    with %{"id" => id, "summary" => summary, "modified" => modified, "published" => published} <-
           advisory,
         {:ok, modified_at, _} <- DateTime.from_iso8601(modified),
         {:ok, published_at, _} <- DateTime.from_iso8601(published) do
      affected =
        advisory
        |> Map.get("affected", [])
        |> Enum.filter(&match?(%{"package" => %{"ecosystem" => "Hex"}}, &1))
        |> Enum.group_by(& &1["package"]["name"])
        |> Enum.flat_map(fn {package_name, entries} -> parse_affected(package_name, entries) end)

      if affected == [] do
        nil
      else
        %{
          id: id,
          summary: summary,
          aliases: Map.get(advisory, "aliases", []),
          published_at: DateTime.truncate(published_at, :second),
          modified_at: DateTime.truncate(modified_at, :second),
          withdrawn_at: parse_withdrawn(advisory),
          cvss_vector: cvss_vector(advisory),
          cvss_score: nil,
          cvss_rating: nil,
          references: parse_references(advisory),
          affected: affected
        }
        |> compute_cvss()
      end
    else
      _ ->
        Logger.warning("Skipping malformed advisory: #{inspect(advisory["id"])}")
        nil
    end
  rescue
    error ->
      Logger.warning("Skipping advisory due to parse error: #{Exception.message(error)}")
      nil
  end

  defp parse_withdrawn(advisory) do
    case Map.get(advisory, "withdrawn") do
      nil ->
        nil

      iso ->
        case DateTime.from_iso8601(iso) do
          {:ok, dt, _} -> DateTime.truncate(dt, :second)
          _ -> nil
        end
    end
  end

  defp parse_references(advisory) do
    advisory
    |> Map.get("references", [])
    |> Enum.flat_map(fn
      %{"type" => type, "url" => url} when is_binary(type) and is_binary(url) ->
        if valid_reference_url?(url), do: [%{type: type, url: url}], else: []

      _ ->
        []
    end)
  end

  defp valid_reference_url?(url) do
    String.length(url) <= @reference_url_max_length and
      case URI.parse(url) do
        %URI{scheme: scheme, host: host}
        when scheme in @reference_url_schemes and is_binary(host) and host != "" ->
          true

        _ ->
          false
      end
  end

  defp cvss_vector(advisory) do
    severities = Map.get(advisory, "severity", [])

    [
      &match?(%{"type" => "CVSS_V4"}, &1),
      &match?(%{"type" => "CVSS_V3"}, &1),
      &match?(%{"type" => "CVSS_V2"}, &1)
    ]
    |> Enum.find_value(fn pred ->
      case Enum.find(severities, pred) do
        %{"score" => vector} when is_binary(vector) -> vector
        _ -> nil
      end
    end)
  end

  defp compute_cvss(%{cvss_vector: nil} = record), do: record

  defp compute_cvss(%{cvss_vector: vector} = record) do
    case :cvss.parse(vector) do
      {:ok, parsed} ->
        %{
          record
          | cvss_score: :cvss.score(parsed),
            cvss_rating: Atom.to_string(:cvss.rating(parsed))
        }

      {:error, reason} ->
        Logger.warning("Failed to parse CVSS vector #{inspect(vector)}: #{inspect(reason)}")
        %{record | cvss_vector: nil}
    end
  end

  defp parse_affected(package_name, entries) do
    requirements =
      entries
      |> Enum.flat_map(&Map.get(&1, "ranges", []))
      |> Enum.flat_map(&parse_range/1)

    versions =
      entries
      |> Enum.flat_map(&Map.get(&1, "versions", []))
      |> Enum.uniq()

    if requirements == [] and versions == [] do
      []
    else
      [%{package: package_name, requirements: requirements, versions: versions}]
    end
  end

  defp parse_range(%{"type" => "SEMVER", "events" => events}) do
    requirement_string =
      events
      |> Enum.reject(&match?(%{"introduced" => "0"}, &1))
      |> Enum.map(fn
        %{"introduced" => version} -> ">= #{pad_version(version)}"
        %{"fixed" => version} -> "< #{pad_version(version)}"
        %{"last_affected" => version} -> "<= #{pad_version(version)}"
        _ -> nil
      end)
      |> Enum.reject(&is_nil/1)
      |> case do
        [] -> ">= 0.0.0"
        parts -> Enum.join(parts, " and ")
      end

    case Version.parse_requirement(requirement_string) do
      {:ok, requirement} -> [requirement]
      :error -> []
    end
  end

  defp parse_range(_), do: []

  defp pad_version(version) do
    case String.split(version, "-", parts: 2) do
      [base, pre] -> "#{pad_base(base)}-#{pre}"
      [base] -> pad_base(base)
    end
  end

  defp pad_base(base) do
    case String.split(base, ".", parts: 3) do
      [_, _, _] -> base
      [_, _] -> "#{base}.0"
      [_] -> "#{base}.0.0"
    end
  end
end
