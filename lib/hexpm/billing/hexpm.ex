defmodule Hexpm.Billing.Hexpm do
  @behaviour Hexpm.Billing

  def checkout(organization, data) do
    case post("/api/customers/#{organization}/payment_source", data, recv_timeout: 15_000) do
      {:ok, 204, _headers, body} -> {:ok, body}
      {:ok, 422, _headers, body} -> {:error, body}
    end
  end

  def get(organization) do
    result =
      fn -> get_json("/api/customers/#{organization}", recv_timeout: 10_000) end
      |> Hexpm.HTTP.retry("billing")

    case result do
      {:ok, 200, _headers, body} -> body
      {:ok, 404, _headers, _body} -> nil
    end
  end

  def cancel(organization) do
    {:ok, 200, _headers, body} = post("/api/customers/#{organization}/cancel", %{}, [])
    body
  end

  def create(params) do
    case post("/api/customers", params, []) do
      {:ok, 200, _headers, body} -> {:ok, body}
      {:ok, 422, _headers, body} -> {:error, body}
    end
  end

  def update(organization, params) do
    case patch("/api/customers/#{organization}", params, []) do
      {:ok, 200, _headers, body} -> {:ok, body}
      {:ok, 404, _headers, _body} -> {:ok, nil}
      {:ok, 422, _headers, body} -> {:error, body}
    end
  end

  def change_plan(organization, params) do
    {:ok, 204, _headers, _body} = post("/api/customers/#{organization}/plan", params, [])
    :ok
  end

  def invoice(id) do
    {:ok, 200, _headers, body} =
      fn -> get_html("/api/invoices/#{id}/html", recv_timeout: 10_000) end
      |> Hexpm.HTTP.retry("billing")

    body
  end

  def pay_invoice(id) do
    result =
      fn -> post("/api/invoices/#{id}/pay", %{}, recv_timeout: 15_000) end
      |> Hexpm.HTTP.retry("billing")

    case result do
      {:ok, 204, _headers, _body} -> :ok
      {:ok, 422, _headers, body} -> {:error, body}
    end
  end

  def report() do
    {:ok, 200, _headers, body} =
      fn -> get_json("/api/reports/customers", []) end
      |> Hexpm.HTTP.retry("billing")

    body
  end

  defp auth() do
    Application.get_env(:hexpm, :billing_key)
  end

  defp post(url, body, opts) do
    url = Application.get_env(:hexpm, :billing_url) <> url

    headers = [
      {"authorization", auth()},
      {"accept", "application/json"},
      {"content-type", "application/json"}
    ]

    body = Jason.encode!(body)

    :hackney.post(url, headers, body, opts)
    |> read_request()
  end

  defp patch(url, body, opts) do
    url = Application.get_env(:hexpm, :billing_url) <> url

    headers = [
      {"authorization", auth()},
      {"accept", "application/json"},
      {"content-type", "application/json"}
    ]

    body = Jason.encode!(body)

    :hackney.patch(url, headers, body, opts)
    |> read_request()
  end

  defp get_json(url, opts) do
    url = Application.get_env(:hexpm, :billing_url) <> url

    headers = [
      {"authorization", auth()},
      {"accept", "application/json"}
    ]

    :hackney.get(url, headers, "", opts)
    |> read_request()
  end

  defp get_html(url, opts) do
    url = Application.get_env(:hexpm, :billing_url) <> url

    headers = [
      {"authorization", auth()},
      {"accept", "text/html"}
    ]

    :hackney.get(url, headers, "", opts)
    |> read_request()
  end

  defp read_request(result) do
    with {:ok, status, headers, ref} <- result,
         headers = normalize_headers(headers),
         {:ok, body} <- :hackney.body(ref),
         {:ok, body} <- decode_body(body, headers) do
      {:ok, status, headers, body}
    end
  end

  defp decode_body(body, headers) do
    case List.keyfind(headers, "content-type", 0) do
      nil ->
        {:ok, nil}

      {_, content_type} ->
        if String.contains?(content_type, "application/json") do
          Jason.decode(body)
        else
          {:ok, body}
        end
    end
  end

  defp normalize_headers(headers) do
    Enum.map(headers, fn {key, value} ->
      {String.downcase(key), value}
    end)
  end
end
