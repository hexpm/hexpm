defmodule Hexpm.Hexdocs.SourceRepo do
  @callback versions(repo :: String.t()) :: {:ok, [Version.t()]} | {:error, term()}

  def versions!(repo) do
    case versions(repo) do
      {:ok, versions} -> versions
      {:error, exception} -> raise exception
    end
  end

  def versions(repo) do
    with {:ok, versions} <- impl().versions(repo) do
      {:ok, Enum.sort(versions, {:desc, Version})}
    end
  end

  defp impl, do: Application.fetch_env!(:hexpm, :hexdocs_source_repo_impl)
end
