defmodule Hexpm.Diff.Cache do
  alias Hexpm.Diff.{Piece, Request}

  @put_options [
    meta: [],
    cache_control: "public, max-age=31536000",
    content_type: "application/json"
  ]

  def fetch(%Request{} = request) do
    case fetch_metadata(request, request.canonical_hash) do
      {:ok, metadata} -> ready(request, request.canonical_hash, metadata)
      :miss -> fetch_legacy(request)
      {:error, _} = error -> error
    end
  end

  def fetch_piece(%Piece{key: key}) do
    case Hexpm.Store.fetch(:diff_bucket, key) do
      :not_found -> {:error, :not_found}
      {:ok, body} -> decode_piece(body)
      {:error, reason} -> {:error, {:storage, reason}}
    end
  end

  def put_piece!(%Request{} = request, index, data) do
    key = diff_key(request, request.canonical_hash, index)
    put!(key, Jason.encode!(data))
    %Piece{id: "diff-#{index}", key: key}
  end

  def put_metadata!(%Request{} = request, metadata) do
    request
    |> metadata_key(request.canonical_hash)
    |> put!(Jason.encode!(metadata))
  end

  def metadata_key(%Request{} = request, hash) do
    "#{repo_prefix(request)}metadata/#{request.package}-#{request.from}-#{request.to}-#{hash}.json"
  end

  def diff_key(%Request{} = request, hash, index) when is_integer(index) do
    "#{repo_prefix(request)}diffs/#{request.package}-#{request.from}-#{request.to}-#{hash}-diff-#{index}.json"
  end

  defp repo_prefix(%Request{repository: "hexpm"}), do: ""
  defp repo_prefix(%Request{repository: repository}), do: "repos/#{repository}/"

  defp fetch_legacy(%Request{canonical_hash: hash, legacy_hash: hash}), do: :miss

  defp fetch_legacy(request) do
    case fetch_metadata(request, request.legacy_hash) do
      {:ok, metadata} -> ready(request, request.legacy_hash, metadata)
      other -> other
    end
  end

  defp fetch_metadata(request, hash) do
    case Hexpm.Store.fetch(:diff_bucket, metadata_key(request, hash)) do
      :not_found -> :miss
      {:ok, body} -> decode_metadata(body)
      {:error, reason} -> {:error, {:storage, reason}}
    end
  end

  defp ready(request, hash, metadata) do
    pieces =
      if metadata.total_diffs == 0 do
        []
      else
        for index <- 0..(metadata.total_diffs - 1) do
          %Piece{
            id: "diff-#{index}",
            key: diff_key(request, hash, index),
            file: Map.get(metadata, :files) && Enum.at(metadata.files, index)
          }
        end
      end

    {:ok, metadata, pieces}
  end

  defp decode_metadata(body) do
    with {:ok, metadata} <- Jason.decode(body),
         {:ok, total_diffs} <- non_negative_integer(metadata["total_diffs"]),
         {:ok, total_additions} <- non_negative_integer(metadata["total_additions"]),
         {:ok, total_deletions} <- non_negative_integer(metadata["total_deletions"]),
         {:ok, files_changed} <- non_negative_integer(metadata["files_changed"]),
         {:ok, files} <- files(metadata["files"], total_diffs) do
      metadata = %{
        total_diffs: total_diffs,
        total_additions: total_additions,
        total_deletions: total_deletions,
        files_changed: files_changed
      }

      {:ok, if(files, do: Map.put(metadata, :files, files), else: metadata)}
    else
      _ -> {:error, :invalid_metadata}
    end
  end

  defp decode_piece(body) do
    case Jason.decode(body) do
      {:ok, %{"type" => "too_large", "file" => file}} when is_binary(file) ->
        {:ok, {:too_large, file}}

      {:ok, %{"diff" => diff, "path_from" => from, "path_to" => to}}
      when is_binary(diff) and is_binary(from) and is_binary(to) ->
        {:ok, {:diff, diff, from, to}}

      _ ->
        {:error, :invalid_piece}
    end
  end

  defp non_negative_integer(value) when is_integer(value) and value >= 0, do: {:ok, value}
  defp non_negative_integer(_), do: :error

  defp files(nil, _total_diffs), do: {:ok, nil}

  defp files(files, total_diffs) when is_list(files) and length(files) == total_diffs do
    if Enum.all?(files, &(is_binary(&1) and &1 != "")), do: {:ok, files}, else: :error
  end

  defp files(_files, _total_diffs), do: :error

  defp put!(key, body) do
    case Hexpm.Store.put(:diff_bucket, key, body, @put_options) do
      :ok -> :ok
      true -> :ok
      {:ok, _result} -> :ok
      result -> raise "failed to store diff object #{key}: #{inspect(result)}"
    end
  end
end
