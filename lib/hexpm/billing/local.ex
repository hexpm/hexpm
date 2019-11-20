defmodule Hexpm.Billing.Local do
  @behaviour Hexpm.Billing

  def create_session(_organization, _success_url, _cancel_url) do
    %{javascript: ""}
  end

  def complete_session(_organization, _session_id, _client_ip) do
    :ok
  end

  def get(_organization) do
    %{
      "monthly_cost" => 800,
      "invoices" => []
    }
  end

  def cancel(_organization) do
    %{}
  end

  def create(_params) do
    {:ok, %{}}
  end

  def update(_organization, _params) do
    {:ok, %{}}
  end

  def change_plan(_organization, _params) do
    :ok
  end

  def invoice(_id) do
    %{}
  end

  def pay_invoice(_id) do
    :ok
  end

  def report() do
    []
  end
end
