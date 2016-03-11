defmodule HexWeb.Script.AddSurrogateKey do
  alias ExAws.S3

  @agent :hexweb_surrogate_agent
  @num_processes 50
  @bucket "hexdocs.pm"

  def main(_args) do
    IO.puts "LISTING"
    all_files = Enum.with_index(list())
    IO.puts "DONE LISTING"

    {:ok, _} = Agent.start_link(fn -> all_files end, name: @agent)

    tasks =
      Enum.map(1..@num_processes, fn _ ->
        Task.async(fn ->
          Enum.each(stream(), fn {path, ix} ->
            Path.split(path)
            |> surrogate_key
            |> copy(path, ix)
          end)
        end)
      end)

    Enum.each(tasks, &Task.await(&1, :infinity))
  end

  defp stream do
    Stream.resource(
      fn -> :ok end,
      fn :ok -> if(elem = next(), do: {[elem], :ok}, else: {:halt, :ok}) end,
      fn :ok -> :ok end)
  end

  defp next do
    Agent.get_and_update(@agent, fn
      [] -> {nil, []}
      [hd|tl] -> {hd, tl}
    end)
  end

  defp copy(nil, _path, _ix), do: :ok
  defp copy(key, path, ix) do
    opts = case Path.extname(path) do
      "." <> ext -> [content_type: Plug.MIME.type(ext)]
      ""         -> []
    end
    |> Keyword.put(:cache_control, "public, max-age=604800")
    |> Keyword.put(:metadata_directive, :REPLACE)
    |> Keyword.put(:meta, [{"surrogate-key", key}])
    |> Keyword.put(:acl, :public_read)

    upload(path, opts, ix)
  end

  defp upload(path, opts, ix) do
    IO.puts "COPY #{ix} #{path}"
    S3.put_object_copy!(@bucket, path, @bucket, path, opts)
    IO.puts "OK   #{ix} #{path}"
  end

  defp surrogate_key([package, version | _]) do
    if Version.parse(version) == :error do
      "docspage/#{package}"
    else
      "docspage/#{package}/#{version}"
    end
  end
  defp surrogate_key(_), do: nil

  defp list do
    S3.stream_objects!(@bucket)
    |> Stream.map(&Map.get(&1, :key))
  end
end

HexWeb.Script.AddSurrogateKey.main(System.argv)
