defmodule Hexpm.Hexdocs.Utils do
  @moduledoc false

  @special_package_names Map.keys(Application.compile_env!(:hexpm, :hexdocs_special_packages))

  def hexdocs_url(repository, package, path) do
    "/" <> _ = path

    if repository == "hexpm" do
      host = Application.fetch_env!(:hexpm, :hexdocs_host)
      scheme = if host == "hexdocs.pm", do: "https", else: "http"
      URI.encode("#{scheme}://#{name_to_subdomain(package)}.#{host}#{path}")
    else
      host = Application.fetch_env!(:hexpm, :hexdocs_private_host)
      scheme = if host in ["hexdocs.pm", "hexorgs.pm"], do: "https", else: "http"
      URI.encode("#{scheme}://#{name_to_subdomain(repository)}.#{host}/#{package}#{path}")
    end
  end

  def name_to_subdomain(name), do: String.replace(name, "_", "-")

  def hexdocs_apex_url(path) do
    "/" <> _ = path
    host = Application.fetch_env!(:hexpm, :hexdocs_host)
    scheme = if host == "hexdocs.pm", do: "https", else: "http"
    URI.encode("#{scheme}://#{host}#{path}")
  end

  def latest_version(versions) do
    Enum.find(versions, &(&1.pre == [])) || List.first(versions)
  end

  def latest_version?(package, version, all_versions) when package in @special_package_names do
    if is_struct(version, Version), do: latest_version?(version, all_versions), else: false
  end

  def latest_version?(_package, version, all_versions), do: latest_version?(version, all_versions)

  defp latest_version?(version, all_versions) do
    cond do
      all_versions == [] ->
        true

      Enum.all?(all_versions, &(&1.pre != [])) ->
        Version.compare(version, List.first(all_versions)) in [:eq, :gt]

      version.pre != [] ->
        false

      true ->
        latest = all_versions |> Enum.filter(&(&1.pre == [])) |> List.first()
        Version.compare(version, latest) in [:eq, :gt]
    end
  end

  def raise_async_stream_error(stream) do
    Stream.each(stream, fn
      {:ok, _result} -> :ok
      {:exit, {_error, stacktrace} = reason} -> reraise(Exception.format_exit(reason), stacktrace)
    end)
  end
end
