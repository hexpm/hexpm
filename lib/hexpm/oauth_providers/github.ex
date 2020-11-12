defmodule Hexpm.OAuthProviders.GitHub do
  @moduledoc """
  Provides an interface for the GitHub OAuth integration
  """
  use Hexpm.Context

  require Logger

  @base_github_access_token_uri "https://github.com/login/oauth/access_token"

  def authorize_uri do
    config = config()

    %URI{
      host: "github.com",
      scheme: "https",
      path: "/login/oauth/authorize",
      query:
        URI.encode_query(%{
          "client_id" => config[:client_id],
          "redirect_uri" => config[:redirect_uri],
          "scope" => config[:scope]
        })
    }
    |> URI.to_string()
  end

  @doc """
  Queries user id from an access_token
  """
  def get_user(token) do
    with {:ok, 200, _headers, body} <-
           Hexpm.HTTP.get("https://api.github.com/user", headers(token)),
         {:ok, decoded_body} <- Jason.decode(body),
         {:ok, user_id} <- Map.fetch(decoded_body, "id"),
         {:ok, email} <- Map.fetch(decoded_body, "email") do
      {:ok, %{id: user_id, email: email}}
    else
      {:ok, status, _headers, body} ->
        Logger.error(
          "[#{__MODULE__}] get_user_id failed with status code: #{inspect(status)} and body #{
            inspect(body)
          }"
        )

        {:error, :http_request_failed}

      {:error, %Jason.DecodeError{}} = error ->
        Logger.error(
          "[#{__MODULE__}] get_user_id failed decoding response with error: #{inspect(error)}"
        )

        error

      error ->
        error
    end
  end

  @doc """
  Get access token for an user from an access code
  """
  def get_access_token(code) do
    with {:ok, 200, _headers, body} <- Hexpm.HTTP.post(authorize_uri(code), headers(), ""),
         {:ok, decoded_body} <- Jason.decode(body),
         {:ok, access_token} <- Map.fetch(decoded_body, "access_token") do
      {:ok, access_token}
    else
      {:ok, status, _headers, body} ->
        Logger.error(
          "[#{__MODULE__}] authorize code failed with status code: #{inspect(status)} and body #{
            inspect(body)
          }"
        )

      {:error, %Jason.DecodeError{}} = error ->
        Logger.error(
          "[#{__MODULE__}] authorize code failed decoding response with error: #{inspect(error)}"
        )

        error

      error ->
        Logger.error(
          "[#{__MODULE__}] authorize code failed with unexpected error: #{inspect(error)}"
        )

        error
    end
  end

  defp authorize_uri(code) do
    config = config()

    query_params =
      URI.encode_query(%{
        "grant_type" => "authorization_code",
        "client_id" => config[:client_id],
        "client_secret" => config[:client_secret],
        "code" => code
      })

    "#{@base_github_access_token_uri}?#{query_params}"
  end

  defp headers do
    [
      {"Content-Type", "application/x-www-form-urlencoded"},
      {"User-Agent", config()[:application_name]},
      {"Accept", "application/json"}
    ]
  end

  defp headers(token), do: [{"Authorization", "token #{token}"} | headers()]

  defp config, do: Application.fetch_env!(:hexpm, __MODULE__)
end
