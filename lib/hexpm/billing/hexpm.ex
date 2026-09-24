defmodule Hexpm.Billing.Hexpm do
  require Logger
  alias Hexpm.HTTP

  @behaviour Hexpm.Billing.Behaviour
  @timeout 15_000

  # TODO: Remove when all customers migrated to SCA/PaymentIntents
  def checkout(organization, data) do
    case post("/api/customers/#{organization}/payment_source", data) do
      {:ok, 204, _headers, body} -> {:ok, body}
      {:ok, 422, _headers, body} -> {:error, body}
      other -> unexpected_response("checkout", organization, other)
    end
  end

  def get(organization, opts \\ []) do
    query = URI.encode_query(Enum.reject(opts, fn {_k, v} -> is_nil(v) end))
    url = "/api/customers/#{organization}?#{query}"

    case get_json(url, retry: []) do
      {:ok, 200, _headers, body} -> body
      {:ok, 404, _headers, _body} -> nil
    end
  end

  def cancel(organization) do
    {:ok, 200, _headers, body} = post("/api/customers/#{organization}/cancel", %{})
    body
  end

  def resume(organization) do
    case post("/api/customers/#{organization}/resume", %{}) do
      {:ok, 200, _headers, body} -> {:ok, body}
      {:ok, status, _headers, body} when status in 400..499 -> {:error, body}
    end
  end

  def create(params) do
    case post("/api/customers", params) do
      {:ok, 200, _headers, body} -> {:ok, body}
      {:ok, 422, _headers, body} -> {:error, body}
      other -> unexpected_response("create", params["token"], other)
    end
  end

  def update(organization, params) do
    case patch("/api/customers/#{organization}", params) do
      {:ok, 200, _headers, body} -> {:ok, body}
      {:ok, 402, _headers, body} -> {:requires_action, body}
      {:ok, 404, _headers, _body} -> {:ok, nil}
      {:ok, 422, _headers, body} -> {:error, body}
      other -> unexpected_response("update", organization, other)
    end
  end

  def void_invoice(organization, payments_token) do
    case post("/api/customers/#{organization}/void_invoice", %{
           "payments_token" => payments_token
         }) do
      {:ok, 204, _headers, _body} -> :ok
      {:ok, status, _headers, body} when status in 400..499 -> {:error, body}
      other -> unexpected_response("void_invoice", organization, other)
    end
  end

  def change_plan(organization, params) do
    case post("/api/customers/#{organization}/plan", params) do
      {:ok, 204, _headers, _body} -> :ok
      {:ok, 422, _headers, body} -> {:error, body}
      other -> unexpected_response("change_plan", organization, other)
    end
  end

  def invoice(id, opts \\ []) do
    query = URI.encode_query(Enum.reject(opts, fn {_k, v} -> is_nil(v) end))
    url = "/api/invoices/#{id}/html?#{query}"

    case get_html(url, retry: [statuses: [500..599]]) do
      {:ok, 200, _headers, body} -> {:ok, body}
      other -> unexpected_response("invoice", id, other)
    end
  end

  def pay_invoice(id) do
    case post("/api/invoices/#{id}/pay", %{}, retry: []) do
      {:ok, 204, _headers, _body} -> :ok
      {:ok, 422, _headers, body} -> {:error, body}
      other -> unexpected_response("pay_invoice", id, other)
    end
  end

  def report() do
    case get_json("/api/reports/customers", retry: [statuses: [500..599]]) do
      {:ok, 200, _headers, body} -> {:ok, body}
      other -> unexpected_response("report", "customers", other)
    end
  end

  # The billing service reports the underlying failure to Sentry, hexpm only
  # needs enough to tie a customer report to a point in time
  defp unexpected_response(operation, context, response) do
    Logger.error([
      "billing ",
      operation,
      " failed for ",
      to_string(context),
      ": ",
      inspect(response)
    ])

    {:error, %{}}
  end

  defp auth() do
    Application.get_env(:hexpm, :billing_key)
  end

  defp post(path, body, opts \\ []) do
    body = JSON.encode!(body)

    headers = [
      {"authorization", auth()},
      {"accept", "application/json"},
      {"content-type", "application/json"}
    ]

    request(:post, path, opts, fn url ->
      HTTP.impl().post(url, headers, body, receive_timeout: @timeout)
    end)
  end

  defp patch(path, body) do
    body = JSON.encode!(body)

    headers = [
      {"authorization", auth()},
      {"accept", "application/json"},
      {"content-type", "application/json"}
    ]

    request(:patch, path, [], fn url ->
      HTTP.impl().patch(url, headers, body, receive_timeout: @timeout)
    end)
  end

  defp get_json(path, opts) do
    headers = [
      {"authorization", auth()},
      {"accept", "application/json"}
    ]

    request(:get, path, opts, fn url ->
      HTTP.impl().get(url, headers, receive_timeout: @timeout)
    end)
  end

  defp get_html(path, opts) do
    headers = [
      {"authorization", auth()},
      {"accept", "text/html"}
    ]

    request(:get, path, opts, fn url ->
      HTTP.impl().get(url, headers, receive_timeout: @timeout)
    end)
  end

  defp request(method, path, opts, fun) do
    url = Application.get_env(:hexpm, :billing_url) <> path

    HTTP.track_request(method, url, fn ->
      case Keyword.fetch(opts, :retry) do
        {:ok, retry_opts} -> HTTP.retry(fn -> fun.(url) end, "billing", retry_opts)
        :error -> fun.(url)
      end
    end)
  end
end
