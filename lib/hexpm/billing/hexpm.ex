defmodule Hexpm.Billing.Hexpm do
  @behaviour Hexpm.Billing

  def checkout(repository, data) do
    {:ok, 204, _headers, body} = post("api/customers/#{repository}/payment_source", data)
    body
  end

  def dashboard(repository) do
    {:ok, 200, _headers, body} = get_json("api/customers/#{repository}")
    body
  end

  def cancel(repository) do
    {:ok, 200, _headers, body} = post("api/customers/#{repository}/cancel", %{})
    body
  end

  def update(repository, params) do
    case patch("api/customers/#{repository}", params) do
      {:ok, 200, _headers, body} -> {:ok, body}
      {:ok, 422, _headers, body} -> {:error, body}
    end
  end

  def invoice(id) do
    {:ok, 200, _headers, body} = get_html("api/invoices/html/#{id}")
    body
  end

  def report() do
    {:ok, 200, _headers, body} = get_json("api/reports/customers")
    body
  end

  defp auth() do
    Application.get_env(:hexpm, :billing_key)
  end

  defp post(url, body) do
    url = Application.get_env(:hexpm, :billing_url) <> url
    headers = [
      {"authorization", auth()},
      {"accept", "application/json"},
      {"content-type", "application/json"}
    ]

    body = Hexpm.Web.Jiffy.encode!(body)
    :hackney.post(url, headers, body, [])
    |> read_request()
  end

  defp patch(url, body) do
    url = Application.get_env(:hexpm, :billing_url) <> url
    headers = [
      {"authorization", auth()},
      {"accept", "application/json"},
      {"content-type", "application/json"}
    ]

    body = Hexpm.Web.Jiffy.encode!(body)
    :hackney.patch(url, headers, body, [])
    |> read_request()
  end

  defp get_json(url) do
    url = Application.get_env(:hexpm, :billing_url) <> url
    headers = [
      {"authorization", auth()},
      {"accept", "application/json"}
    ]

    :hackney.get(url, headers, [])
    |> read_request()
  end

  defp get_html(url) do
    url = Application.get_env(:hexpm, :billing_url) <> url
    headers = [
      {"authorization", auth()},
      {"accept", "text/html"}
    ]

    :hackney.get(url, headers, [])
    |> read_request()
  end

  defp read_request(result) do
    with {:ok, status, headers, ref} <- result,
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
          Hexpm.Web.Jiffy.decode(body)
        else
          {:ok, body}
        end
    end
  end
end
