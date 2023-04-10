defmodule Hexpm.Billing.Hexpm do
  alias Hexpm.HTTP

  @behaviour Hexpm.Billing.Behaviour
  @timeout 15_000

  def checkout(organization, data) do
    case post("/api/customers/#{organization}/payment_source", data) do
      {:ok, 204, _headers, body} -> {:ok, body}
      {:ok, 422, _headers, body} -> {:error, body}
    end
  end

  def get(organization) do
    result =
      fn -> get_json("/api/customers/#{organization}") end
      |> Hexpm.HTTP.retry("billing")

    case result do
      {:ok, 200, _headers, body} -> body
      {:ok, 404, _headers, _body} -> nil
    end
  end

  def cancel(organization) do
    {:ok, 200, _headers, body} = post("/api/customers/#{organization}/cancel", %{})
    body
  end

  def create(params) do
    case post("/api/customers", params) do
      {:ok, 200, _headers, body} -> {:ok, body}
      {:ok, 422, _headers, body} -> {:error, body}
    end
  end

  def update(organization, params) do
    case patch("/api/customers/#{organization}", params) do
      {:ok, 200, _headers, body} -> {:ok, body}
      {:ok, 404, _headers, _body} -> {:ok, nil}
      {:ok, 422, _headers, body} -> {:error, body}
    end
  end

  def change_plan(organization, params) do
    {:ok, 204, _headers, _body} = post("/api/customers/#{organization}/plan", params)
    :ok
  end

  def invoice(id) do
    {:ok, 200, _headers, body} =
      fn -> get_html("/api/invoices/#{id}/html") end
      |> Hexpm.HTTP.retry("billing")

    body
  end

  def pay_invoice(id) do
    result =
      fn -> post("/api/invoices/#{id}/pay", %{}) end
      |> Hexpm.HTTP.retry("billing")

    case result do
      {:ok, 204, _headers, _body} -> :ok
      {:ok, 422, _headers, body} -> {:error, body}
    end
  end

  def report() do
    {:ok, 200, _headers, body} =
      fn -> get_json("/api/reports/customers") end
      |> Hexpm.HTTP.retry("billing")

    body
  end

  defp auth() do
    Application.get_env(:hexpm, :billing_key)
  end

  defp post(url, body) do
    url = Application.get_env(:hexpm, :billing_url) <> url
    body = Jason.encode!(body)

    headers = [
      {"authorization", auth()},
      {"accept", "application/json"},
      {"content-type", "application/json"}
    ]

    HTTP.impl().post(url, headers, body, receive_timeout: @timeout)
  end

  defp patch(url, body) do
    url = Application.get_env(:hexpm, :billing_url) <> url
    body = Jason.encode!(body)

    headers = [
      {"authorization", auth()},
      {"accept", "application/json"},
      {"content-type", "application/json"}
    ]

    HTTP.impl().patch(url, headers, body, receive_timeout: @timeout)
  end

  defp get_json(url) do
    url = Application.get_env(:hexpm, :billing_url) <> url

    headers = [
      {"authorization", auth()},
      {"accept", "application/json"}
    ]

    HTTP.impl().get(url, headers, receive_timeout: @timeout)
  end

  defp get_html(url) do
    url = Application.get_env(:hexpm, :billing_url) <> url

    headers = [
      {"authorization", auth()},
      {"accept", "text/html"}
    ]

    HTTP.impl().get(url, headers, receive_timeout: @timeout)
  end
end
