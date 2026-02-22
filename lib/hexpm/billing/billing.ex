defmodule Hexpm.Billing do
  use Hexpm.Context

  defp impl(), do: Application.get_env(:hexpm, :billing_impl)

  # TODO: Remove when all customers migrated to SCA/PaymentIntents
  def checkout(organization, data), do: impl().checkout(organization, data)
  def get(organization), do: impl().get(organization)
  def cancel(organization), do: impl().cancel(organization)
  def create(params), do: impl().create(params)
  def update(organization, params), do: impl().update(organization, params)
  def change_plan(organization, params), do: impl().change_plan(organization, params)
  def invoice(id), do: impl().invoice(id)
  def pay_invoice(id), do: impl().pay_invoice(id)
  def report(), do: impl().report()
  def pending_payment_action(organization), do: impl().pending_payment_action(organization)

  # TODO: Remove when all customers migrated to SCA/PaymentIntents
  def checkout(organization_name, data,
        audit: %{audit_data: audit_data, organization: organization}
      ) do
    case impl().checkout(organization_name, data) do
      {:ok, body} ->
        Repo.insert!(audit(audit_data, "billing.checkout", {organization, data}))
        {:ok, body}

      {:error, reason} ->
        {:error, reason}
    end
  end

  def cancel(params, audit: %{audit_data: audit_data, organization: organization}) do
    result = impl().cancel(params)
    Repo.insert!(audit(audit_data, "billing.cancel", {organization, params}))
    result
  end

  def resume(organization_name, audit: %{audit_data: audit_data, organization: organization}) do
    case impl().resume(organization_name) do
      {:ok, result} ->
        Repo.insert!(audit(audit_data, "billing.resume", {organization, organization_name}))
        {:ok, result}

      {:error, reason} ->
        {:error, reason}
    end
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

      {:requires_action, result} ->
        {:requires_action, result}

      {:error, reason} ->
        {:error, reason}
    end
  end

  def void_invoice(payments_token) do
    impl().void_invoice(payments_token)
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
