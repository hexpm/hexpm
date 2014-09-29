defmodule HexWeb.Tar do
  # The release tar contains the following files:
  # VERSION             - release tar version
  # CHECKSUM            - checksum of file contents sha256(VERSION <> metadata.exs <> contents.tar.gz)
  #     metadata.exs    - release metadata as single elixir map (VERSION 2)
  #  OR metadata.config - release metadata in erlang term file (VERSION 3)
  # contents.tar.gz     - gzipped tar file of all files bundled in the release

  @files_2 ["VERSION", "CHECKSUM", "metadata.exs", "contents.tar.gz"]
  @files_3 ["VERSION", "CHECKSUM", "metadata.config", "contents.tar.gz"]

  defmacrop if_ok(expr, call) do
    quote do
      case unquote(expr) do
        {:ok, var1, var2} ->
          unquote(Macro.pipe(quote(do: var1), Macro.pipe(quote(do: var2), call, 0), 0))
        other -> other
      end
    end
  end

  def metadata(binary) do
    case :erl_tar.extract({:binary, binary}, [:memory]) do
      {:ok, files} ->
        files = Enum.into(files, %{}, fn {name, binary} -> {List.to_string(name), binary} end)

        meta = version(files)
               |> if_ok(checksum)
               |> if_ok(missing_files)
               |> if_ok(unknown_files)
               |> if_ok(meta)

        case meta do
          {:ok, meta} ->
            {:ok, meta, files["CHECKSUM"]}
          error ->
            error
        end

      {:error, reason} ->
        {:error, inspect reason}
    end
  end

  defp version(files) do
    version = files["VERSION"]
    if version in ["2", "3"] do
      {:ok, files, String.to_integer(version)}
    else
      {:error, %{version: :not_supported}}
    end
  end

  defp checksum(files, version) do
    case Base.decode16(files["CHECKSUM"], case: :mixed) do
      {:ok, ref_checksum} ->
        metadata = metadata_file(version)
        blob = files["VERSION"] <> files[metadata] <> files["contents.tar.gz"]

        if :crypto.hash(:sha256, blob) == ref_checksum do
          {:ok, files, version}
        else
          {:error, %{checksum: :mismatch}}
        end

      :error ->
        {:error, %{checksum: :invalid}}
    end
  end

  defp missing_files(files, version) do
    expected_files = expected_files(version)
    missing_files = Enum.reject(expected_files, &Dict.has_key?(files, &1))

    if length(missing_files) == 0 do
      {:ok, files, version}
    else
      {:error, %{missing_files: missing_files}}
    end
  end

  defp unknown_files(files, version) do
    expected_files = expected_files(version)
    unknown_files = Enum.reject(files, fn {name, _binary} -> name in expected_files end)

    if length(unknown_files) == 0 do
      {:ok, files, version}
    else
      names = Enum.map(unknown_files, &elem(&1, 0))
      {:error, %{unknown_files: names}}
    end
  end

  defp meta(files, 2) do
    case HexWeb.API.ElixirFormat.decode(files["metadata.exs"]) do
      {:ok, result}    -> {:ok, result}
      {:error, reason} -> {:error, %{metadata: reason}}
    end
  end

  defp meta(files, 3) do
    case HexWeb.API.ConsultFormat.decode(files["metadata.config"]) do
      {:ok, result}    -> {:ok, result}
      {:error, reason} -> {:error, %{metadata: reason}}
    end
  end

  defp expected_files(2), do: @files_2
  defp expected_files(3), do: @files_3

  defp metadata_file(2), do: "metadata.exs"
  defp metadata_file(3), do: "metadata.config"
end
