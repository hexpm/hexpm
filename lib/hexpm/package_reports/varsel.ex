defmodule Hexpm.PackageReports.Varsel do
  @callback submit(map()) ::
              {:ok, %{id: String.t(), url: String.t(), sign_in_url: String.t()}}
              | {:error, :unavailable}

  def submit(report), do: impl().submit(report)

  defp impl, do: Application.fetch_env!(:hexpm, :varsel_impl)
end

defmodule Hexpm.PackageReports.Varsel.Client do
  @behaviour Hexpm.PackageReports.Varsel

  require Logger

  @timeout 15_000
  @max_body_bytes 32_000

  @impl true
  def submit(report) do
    config = Application.fetch_env!(:hexpm, :varsel)
    url = Keyword.fetch!(config, :report_url)

    with {:ok, token} <- token(config),
         body <- JSON.encode!(report),
         {:ok, 201, headers, response} <-
           Hexpm.HTTP.impl().post(url, request_headers(token), body,
             receive_timeout: @timeout,
             request_timeout: @timeout,
             max_body_bytes: @max_body_bytes
           ),
         {:ok, result} <- validate_response(url, headers, response) do
      {:ok, result}
    else
      error ->
        Logger.error("Varsel package report submission failed: #{failure_reason(error)}")
        {:error, :unavailable}
    end
  rescue
    error ->
      Logger.error("Varsel package report submission failed: #{inspect(error.__struct__)}")
      {:error, :unavailable}
  end

  defp token(config) do
    now = System.system_time(:second)

    claims = %{
      "aud" => Keyword.fetch!(config, :audience),
      "exp" => now + 60,
      "iat" => now,
      "iss" => "hexpm",
      "jti" => Ecto.UUID.generate(),
      "nbf" => now - 5,
      "sub" => "hexpm"
    }

    signer =
      Joken.Signer.create(
        "ES256",
        %{
          "pem" =>
            Keyword.get_lazy(config, :signing_key, fn ->
              Application.fetch_env!(:hexpm, :jwt_signing_key)
            end)
        },
        %{"kid" => Keyword.fetch!(config, :key_id)}
      )

    Joken.Signer.sign(claims, signer)
  end

  defp request_headers(token) do
    [
      {"authorization", "Bearer #{token}"},
      {"accept", "application/json"},
      {"content-type", "application/json"}
    ]
  end

  defp validate_response(report_url, headers, %{
         "id" => id,
         "url" => url,
         "sign_in_url" => sign_in_url
       })
       when is_binary(id) and id != "" and is_binary(url) and is_binary(sign_in_url) do
    location = header(headers, "location")

    if location == url and same_origin?(report_url, url) and same_origin?(report_url, sign_in_url) do
      {:ok, %{id: id, url: url, sign_in_url: sign_in_url}}
    else
      {:error, :invalid_response}
    end
  end

  defp validate_response(_report_url, _headers, _response), do: {:error, :invalid_response}

  defp failure_reason({:ok, status, _headers, _body}) when is_integer(status),
    do: "HTTP status #{status}"

  defp failure_reason({:error, reason}) when is_atom(reason), do: Atom.to_string(reason)
  defp failure_reason({:error, %{__struct__: module}}), do: inspect(module)
  defp failure_reason({:error, _reason}), do: "request error"
  defp failure_reason(_error), do: "invalid response"

  defp header(headers, name) do
    Enum.find_value(headers, fn {header_name, value} ->
      String.downcase(header_name) == name && value
    end)
  end

  defp same_origin?(left, right) do
    left = URI.parse(left)
    right = URI.parse(right)

    right.scheme == "https" and
      {left.scheme, left.host, effective_port(left)} ==
        {right.scheme, right.host, effective_port(right)}
  end

  defp effective_port(%URI{port: port}) when is_integer(port), do: port
  defp effective_port(%URI{scheme: "https"}), do: 443
  defp effective_port(%URI{scheme: "http"}), do: 80
  defp effective_port(_uri), do: nil
end
