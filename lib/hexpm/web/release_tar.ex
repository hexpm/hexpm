defmodule Hexpm.Web.ReleaseTar do
  # The release tar contains the following files:
  # VERSION         - release tar version
  # CHECKSUM        - checksum of file contents sha256(VERSION <> metadata.exs <> contents.tar.gz)
  # metadata.config - release metadata in erlang term file
  # contents.tar.gz - gzipped tar file of all files bundled in the release

  @files ["VERSION", "CHECKSUM", "metadata.config", "contents.tar.gz"]
  @tar_max_size 8 * 1024 * 1024

  defmacrop if_ok(expr, call) do
    quote do
      case unquote(expr) do
        {:ok, var1, var2} ->
          unquote(Macro.pipe(quote(do: var1), Macro.pipe(quote(do: var2), call, 0), 0))
        other -> other
      end
    end
  end

  def metadata(binary) when byte_size(binary) > @tar_max_size do
    {:error, :too_big}
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
    if version in ["3"] do
      {:ok, files, String.to_integer(version)}
    else
      {:error, %{version: :not_supported}}
    end
  end

  defp checksum(files, version) do
    case Base.decode16(files["CHECKSUM"], case: :mixed) do
      {:ok, ref_checksum} ->
        blob = files["VERSION"] <> files["metadata.config"] <> files["contents.tar.gz"]

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
    missing_files = Enum.reject(@files, &Map.has_key?(files, &1))

    if length(missing_files) == 0 do
      {:ok, files, version}
    else
      {:error, %{missing_files: missing_files}}
    end
  end

  defp unknown_files(files, version) do
    unknown_files = Enum.reject(files, fn {name, _binary} -> name in @files end)

    if length(unknown_files) == 0 do
      {:ok, files, version}
    else
      names = Enum.map(unknown_files, &elem(&1, 0))
      {:error, %{unknown_files: names}}
    end
  end

  defp meta(files, _version) do
    case Hexpm.Web.ConsultFormat.decode(files["metadata.config"]) do
      {:ok, meta} ->
        meta =
          meta
          |> proplists_to_maps
          |> guess_build_tool
        {:ok, meta}
      {:error, reason} ->
        {:error, %{metadata: reason}}
    end
  end

  defp proplists_to_maps(meta) do
    meta
    |> try_update("links", &try_into_map(&1))
    |> try_update("extra", &try_into_map(&1))
    |> try_update("requirements", fn reqs ->
         if is_list(reqs) and is_list(List.first(reqs)) do
           Enum.map(reqs, &try_into_map/1)
         else
           try_into_map(reqs, fn {key, value} ->
             {key, try_into_map(value)}
           end)
         end
       end)
  end

  @build_tools [
    {"mix.exs"     , "mix"},
    {"rebar.config", "rebar"},
    {"rebar"       , "rebar"},
    {"Makefile"    , "make"},
    {"Makefile.win", "make"}
  ]

  defp guess_build_tool(%{"build_tools" => _} = meta) do
    meta
  end

  defp guess_build_tool(meta) do
    base_files =
      (meta["files"] || [])
      |> Enum.filter(&(Path.dirname(&1) == "."))
      |> MapSet.new

    build_tools =
      Enum.flat_map(@build_tools, fn {file, tool} ->
        if file in base_files,
            do: [tool],
          else: []
      end)
      |> Enum.uniq

    if build_tools != [] do
      Map.put(meta, "build_tools", build_tools)
    else
      meta
    end
  end

  defp try_update(map, key, fun) do
    case Map.fetch(map, key) do
      {:ok, value} -> Map.put(map, key, fun.(value))
      :error -> map
    end
  end

  defp try_into_map(input, fun \\ fn x -> x end) do
    if is_list(input) and Enum.all?(input, &(is_tuple(&1) and tuple_size(&1) == 2)) do
      Enum.into(input, %{}, fun)
    else
      input
    end
  end
end
