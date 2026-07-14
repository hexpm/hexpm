defmodule Hexpm.Hexdocs.SourceRepo.GitHub do
  @behaviour Hexpm.Hexdocs.SourceRepo
  @github_url "https://api.github.com"

  @impl true
  def versions(repo) do
    user = Application.get_env(:hexpm, :hexdocs_github_user)
    token = Application.get_env(:hexpm, :hexdocs_github_token)
    url = @github_url <> "/repos/#{repo}/tags"
    credentials = Base.encode64("#{user}:#{token}")
    headers = [{"accept", "application/json"}, {"authorization", "Basic " <> credentials}]

    Hexpm.HTTP.retry(
      fn -> Hexpm.HTTP.impl().get(url, headers) end,
      "github #{url}",
      attempts: 5,
      base_delay: 200,
      statuses: [429, 500..599]
    )
    |> case do
      {:ok, 200, _headers, body} ->
        versions =
          for %{"name" => "v" <> version} <- decode(body),
              not String.ends_with?(version, "-latest") do
            Version.parse!(version)
          end

        {:ok, versions}

      {:ok, status, _headers, body} ->
        {:error, RuntimeError.exception("http unexpected status #{status}: #{inspect(body)}")}

      {:error, reason} ->
        {:error, RuntimeError.exception("http error: #{inspect(reason)}")}
    end
  end

  defp decode(body) when is_binary(body), do: Jason.decode!(body)
  defp decode(body), do: body
end
