defmodule Hexpm.Billing do
  use Hexpm.Context

  @type organization() :: String.t()

  @callback create_session(organization(), String.t(), String.t()) :: map()
  @callback complete_session(organization(), String.t(), String.t()) :: :ok | {:error, map()}
  @callback get(organization()) :: map() | nil
  @callback cancel(organization()) :: map()
  @callback create(map()) :: {:ok, map()} | {:error, map()}
  @callback update(organization(), map()) :: {:ok, map()} | {:error, map()}
  @callback change_plan(organization(), map()) :: :ok
  @callback invoice(id :: pos_integer()) :: binary()
  @callback pay_invoice(id :: pos_integer()) :: :ok | {:error, map()}
  @callback report() :: [map()]

  defp impl(), do: Application.get_env(:hexpm, :billing_impl)

  def create_session(organization, success_url, cancel_url),
    do: impl().create_session(organization, success_url, cancel_url)

  def complete_session(organization, session_id, client_ip),
    do: impl().complete_session(organization, session_id, client_ip)

  def get(organization), do: impl().get(organization)
  def cancel(organization), do: impl().cancel(organization)
  def create(params), do: impl().create(params)
  def update(organization, params), do: impl().update(organization, params)
  def change_plan(organization, params), do: impl().change_plan(organization, params)
  def invoice(id), do: impl().invoice(id)
  def pay_invoice(id), do: impl().pay_invoice(id)
  def report(), do: impl().report()

  @doc """
  Change payment method used by an organization.
  """
  def complete_session(organization_name, session_id, client_ip,
        audit: %{audit_data: audit_data, organization: organization}
      ) do
    case complete_session(organization_name, session_id, client_ip) do
      :ok ->
        Repo.insert!(audit(audit_data, "billing.checkout", {organization, session_id, client_ip}))
        :ok

      {:error, reason} ->
        {:error, reason}
    end
  end

  def cancel(params, audit: %{audit_data: audit_data, organization: organization}) do
    result = impl().cancel(params)
    Repo.insert!(audit(audit_data, "billing.cancel", {organization, params}))
    result
  end

  def create(params, audit: %{audit_data: audit_data, organization: organization}) do
    case impl().create(params) do
      {:ok, result} ->
        Repo.insert!(audit(audit_data, "billing.create", {organization, params}))
        {:ok, result}

      {:error, reason} ->
        {:error, reason}
    end
  end

  def update(organization_name, params,
        audit: %{audit_data: audit_data, organization: organization}
      ) do
    case impl().update(organization_name, params) do
      {:ok, result} ->
        Repo.insert!(audit(audit_data, "billing.update", {organization, params}))
        {:ok, result}

      {:error, reason} ->
        {:error, reason}
    end
  end

  def change_plan(organization_name, params,
        audit: %{audit_data: audit_data, organization: organization}
      ) do
    impl().change_plan(organization_name, params)
    Repo.insert!(audit(audit_data, "billing.change_plan", {organization, params}))
    :ok
  end

  def pay_invoice(id, audit: %{audit_data: audit_data, organization: organization}) do
    case impl().pay_invoice(id) do
      :ok ->
        Repo.insert!(audit(audit_data, "billing.pay_invoice", {organization, id}))
        :ok

      {:error, reason} ->
        {:error, reason}
    end
  end
end
