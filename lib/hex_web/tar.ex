defmodule HexWeb.Tar do
  # The release tar contains the following files:
  # VERSION - release tar version
  # CHECKSUM - checksum of file contents md5(VERSION <> metadata.exs <> contents.tar.gz)
  # metadata.exs - release metadata
  # contents.tar.gz - gzipped tar file of all files bundled in the release

  @files ["VERSION", "CHECKSUM", "metadata.exs", "contents.tar.gz"]

  defmacrop if_ok(expr, call) do
    quote do
      case unquote(expr) do
        { :ok, var1, var2 } ->
          unquote(Macro.pipe(quote(do: var1), Macro.pipe(quote(do: var2), call, 0), 0))
        other -> other
      end
    end
  end

  def metadata(binary) do
    case :erl_tar.extract({ :binary, binary }, [:memory, :cooked]) do
      { :ok, files } ->
        files = Enum.into(files, %{}, fn { name, binary } -> { String.from_char_data!(name), binary } end)

        version(files)
        |> if_ok(checksum)
        |> if_ok(missing_files)
        |> if_ok(unknown_files)
        |> if_ok(meta)

      { :error, reason } ->
        { :error, %{tar: inspect reason} }
    end
  end

  defp version(files) do
    version = files["VERSION"]
    if version in ["1", "2"] do
      { :ok, files, binary_to_integer(version) }
    else
      { :error, %{version: :wrong} }
    end
  end

  defp checksum(files, version) do
    blob = files["VERSION"] <> files["metadata.exs"] <> files["contents.tar.gz"]
    if hash(blob, version) == HexWeb.Util.dehexify(files["CHECKSUM"]) do
      { :ok, files, version }
    else
      { :error, %{checksum: :wrong} }
    end
  end

  defp missing_files(files, version) do
    missing_files = Enum.reject(@files, &Dict.has_key?(files, &1))
    if length(missing_files) == 0 do
      { :ok, files, version }
    else
      { :error, %{missing_files: missing_files} }
    end
  end

  defp unknown_files(files, version) do
    unknown_files = Enum.reject(files, fn { name, _binary } -> name in @files end)
    if length(unknown_files) == 0 do
      { :ok, files, version }
    else
      names = Enum.map(unknown_files, &elem(&1, 0))
      { :error, %{unknown_files: names} }
    end
  end

  defp meta(files, _version) do
    try do
      { :ok, HexWeb.Util.safe_deserialize_elixir(files["metadata.exs"]) }
    rescue
      err in [HexWeb.Util.BadRequest] ->
        { :error, %{metadata: err.message} }
    end
  end

  defp hash(blob, 1) do
    :crypto.hash(:md5, blob)
  end

  defp hash(blob, 2) do
    :crypto.hash(:sha256, blob)
  end
end
