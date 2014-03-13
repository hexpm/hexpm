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
        { :ok, var } -> unquote(Macro.pipe(quote(do: var), call))
        other -> other
      end
    end
  end

  def metadata(binary) do
    case :erl_tar.extract({ :binary, binary }, [:memory, :cooked]) do
      { :ok, files } ->
        files = Enum.map(files, fn { name, binary } -> { String.from_char_list!(name), binary } end)

        missing_files(files)
        |> if_ok(unknown_files)
        |> if_ok(checksum)
        |> if_ok(version)
        |> if_ok(meta)

      { :error, reason } ->
        { :error, [tar: inspect reason] }
    end
  end

  defp missing_files(files) do
    missing_files = Enum.reject(@files, &Dict.has_key?(files, &1))
    if length(missing_files) == 0 do
      { :ok, files }
    else
      { :error, [missing_files: missing_files] }
    end
  end

  defp unknown_files(files) do
    unknown_files = Enum.reject(files, fn { name, _binary } -> name in @files end)
    if length(unknown_files) == 0 do
      { :ok, files }
    else
      names = Enum.map(unknown_files, &elem(&1, 0))
      { :error, [unknown_files: names] }
    end
  end

  defp checksum(files) do
    blob = files["VERSION"] <> files["metadata.exs"] <> files["contents.tar.gz"]
    if :crypto.hash(:md5, blob) == HexWeb.Util.dehexify(files["CHECKSUM"]) do
      { :ok, files }
    else
      { :error, [checksum: :wrong] }
    end
  end

  defp version(files) do
    if files["VERSION"] == "1" do
      { :ok, files }
    else
      { :error, [version: :wrong] }
    end
  end

  defp meta(files) do
    try do
      { :ok, HexWeb.Util.safe_deserialize_elixir(files["metadata.exs"]) }
    rescue
      err in [HexWeb.Util.BadRequest] ->
        { :error, [metadata: err.message] }
    end
  end
end
