defmodule Hexpm.Hexdocs.Utils do
  @moduledoc false

  @special_package_names Map.keys(Application.compile_env!(:hexpm, :hexdocs_special_packages))

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
