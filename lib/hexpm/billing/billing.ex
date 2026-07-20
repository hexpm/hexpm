defmodule Hexpm.Billing do
  use Hexpm.Context

  defp impl(), do: Application.get_env(:hexpm, :billing_impl)

  # TODO: Remove when all customers migrated to SCA/PaymentIntents
  def checkout(organization, data) do
    Repo.write_mode!()
    impl().checkout(organization, data)
  end

  def get(organization, opts \\ []), do: impl().get(organization, opts)

  def cancel(organization) do
    Repo.write_mode!()
    impl().cancel(organization)
  end

  def create(params) do
    Repo.write_mode!()
    impl().create(params)
  end

  def update(organization, params) do
    Repo.write_mode!()
    impl().update(organization, params)
  end

  def change_plan(organization, params) do
    Repo.write_mode!()
    impl().change_plan(organization, params)
  end

  def invoice(id, opts \\ []), do: impl().invoice(id, opts)

  def pay_invoice(id) do
    Repo.write_mode!()
    impl().pay_invoice(id)
  end

  def report(), do: impl().report()

  # TODO: Remove when all customers migrated to SCA/PaymentIntents
  def checkout(organization_name, data,
        audit: %{audit_data: audit_data, organization: organization}
      ) do
    Repo.write_mode!()

    case impl().checkout(organization_name, data) do
      {:ok, body} ->
        Repo.insert!(audit(audit_data, "billing.checkout", {organization, data}))
        {:ok, body}

      {:error, reason} ->
        {:error, reason}
    end
  end

  def cancel(params, audit: %{audit_data: audit_data, organization: organization}) do
    Repo.write_mode!()
    result = impl().cancel(params)
    Repo.insert!(audit(audit_data, "billing.cancel", {organization, params}))
    result
  end

  def resume(organization_name, audit: %{audit_data: audit_data, organization: organization}) do
    Repo.write_mode!()

    case impl().resume(organization_name) do
      {:ok, result} ->
        Repo.insert!(audit(audit_data, "billing.resume", {organization, organization_name}))
        {:ok, result}

      {:error, reason} ->
        {:error, reason}
    end
  end

  def create(params, audit: %{audit_data: audit_data, organization: organization}) do
    Repo.write_mode!()

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
    Repo.write_mode!()

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

  def void_invoice(organization, payments_token) do
    Repo.write_mode!()
    impl().void_invoice(organization, payments_token)
  end

  def change_plan(organization_name, params,
        audit: %{audit_data: audit_data, organization: organization}
      ) do
    Repo.write_mode!()

    case impl().change_plan(organization_name, params) do
      :ok ->
        Repo.insert!(audit(audit_data, "billing.change_plan", {organization, params}))
        :ok

      {:error, reason} ->
        {:error, reason}
    end
  end

  def pay_invoice(id, audit: %{audit_data: audit_data, organization: organization}) do
    Repo.write_mode!()

    case impl().pay_invoice(id) do
      :ok ->
        Repo.insert!(audit(audit_data, "billing.pay_invoice", {organization, id}))
        :ok

      {:error, reason} ->
        {:error, reason}
    end
  end
end
