defmodule Hexpm.Web.Dashboard.RepositoryController do
  use Hexpm.Web, :controller

  plug :requires_login

  def show(conn, %{"dashboard_repo" => repository}) do
    access_repository(conn, repository, "read", fn repository ->
      render_index(conn, repository)
    end)
  end

  def update(conn, %{
        "dashboard_repo" => repository,
        "action" => "add_member",
        "repository_user" => params
      }) do
    username = params["username"]

    access_repository(conn, repository, "admin", fn repository ->
      case Repositories.add_member(repository, username, params, audit: audit_data(conn)) do
        {:ok, _} ->
          members_count = Repositories.members_count(repository)
          {:ok, _customer} = Hexpm.Billing.update(repository.name, %{"quantity" => members_count})

          conn
          |> put_flash(:info, "User #{username} has been added to the organization.")
          |> redirect(to: Routes.repository_path(conn, :show, repository))

        {:error, :unknown_user} ->
          conn
          |> put_status(400)
          |> put_flash(:error, "Unknown user #{username}.")
          |> render_index(repository)

        {:error, changeset} ->
          conn
          |> put_status(400)
          |> render_index(repository, add_member: changeset)
      end
    end)
  end

  def update(conn, %{
        "dashboard_repo" => repository,
        "action" => "remove_member",
        "repository_user" => params
      }) do
    # TODO: Also remove all package ownerships on repository for removed member
    username = params["username"]

    access_repository(conn, repository, "admin", fn repository ->
      case Repositories.remove_member(repository, username, audit: audit_data(conn)) do
        :ok ->
          members_count = Repositories.members_count(repository)
          {:ok, _customer} = Hexpm.Billing.update(repository.name, %{"quantity" => members_count})

          conn
          |> put_flash(:info, "User #{username} has been removed from the organization.")
          |> redirect(to: Routes.repository_path(conn, :show, repository))

        {:error, reason} ->
          conn
          |> put_status(400)
          |> put_flash(:error, remove_member_error_message(reason, username))
          |> render_index(repository)
      end
    end)
  end

  def update(conn, %{
        "dashboard_repo" => repository,
        "action" => "change_role",
        "repository_user" => params
      }) do
    username = params["username"]

    access_repository(conn, repository, "admin", fn repository ->
      case Repositories.change_role(repository, username, params, audit: audit_data(conn)) do
        {:ok, _} ->
          conn
          |> put_flash(:info, "User #{username}'s role has been changed to #{params["role"]}.")
          |> redirect(to: Routes.repository_path(conn, :show, repository))

        {:error, :unknown_user} ->
          conn
          |> put_status(400)
          |> put_flash(:error, "Unknown user #{username}.")
          |> render_index(repository)

        {:error, :last_admin} ->
          conn
          |> put_status(400)
          |> put_flash(:error, "Cannot demote last admin member.")
          |> render_index(repository)

        {:error, changeset} ->
          conn
          |> put_status(400)
          |> render_index(repository, change_role: changeset)
      end
    end)
  end

  def billing_token(conn, %{"dashboard_repo" => repository, "token" => token}) do
    access_repository(conn, repository, "admin", fn repository ->
      case Hexpm.Billing.checkout(repository.name, %{payment_source: token}) do
        {:ok, _} ->
          conn
          |> put_resp_header("content-type", "application/json")
          |> send_resp(204, Jason.encode!(%{}))

        {:error, reason} ->
          conn
          |> put_resp_header("content-type", "application/json")
          |> send_resp(422, Jason.encode!(reason))
      end
    end)
  end

  def cancel_billing(conn, %{"dashboard_repo" => repository}) do
    access_repository(conn, repository, "admin", fn repository ->
      billing = Hexpm.Billing.cancel(repository.name)

      cancel_date =
        billing["subscription"]["current_period_end"]
        |> Hexpm.Web.Dashboard.RepositoryView.payment_date()

      message =
        "Your subscription is cancelled, you will have access to the repository until " <>
          "the end of your billing period at #{cancel_date}"

      conn
      |> put_flash(:info, message)
      |> redirect(to: Routes.repository_path(conn, :show, repository))
    end)
  end

  def show_invoice(conn, %{"dashboard_repo" => repository, "id" => id}) do
    access_repository(conn, repository, "admin", fn repository ->
      id = String.to_integer(id)
      billing = Hexpm.Billing.dashboard(repository.name)
      invoice_ids = Enum.map(billing["invoices"], & &1["id"])

      if id in invoice_ids do
        invoice = Hexpm.Billing.invoice(id)

        conn
        |> put_resp_header("content-type", "text/html")
        |> send_resp(200, invoice)
      else
        not_found(conn)
      end
    end)
  end

  def pay_invoice(conn, %{"dashboard_repo" => repository, "id" => id}) do
    access_repository(conn, repository, "admin", fn repository ->
      id = String.to_integer(id)
      billing = Hexpm.Billing.dashboard(repository.name)
      invoice_ids = Enum.map(billing["invoices"], & &1["id"])

      if id in invoice_ids do
        case Hexpm.Billing.pay_invoice(id) do
          :ok ->
            conn
            |> put_flash(:info, "Invoice paid.")
            |> redirect(to: Routes.repository_path(conn, :show, repository))

          {:error, reason} ->
            conn
            |> put_status(400)
            |> put_flash(:error, "Failed to pay invoice: #{reason["errors"]}.")
            |> render_index(repository)
        end
      else
        not_found(conn)
      end
    end)
  end

  def update_billing(conn, %{"dashboard_repo" => repository} = params) do
    access_repository(conn, repository, "admin", fn repository ->
      update_billing(
        conn,
        repository,
        params,
        &Hexpm.Billing.update(repository.name, &1)
      )
    end)
  end

  def create_billing(conn, %{"dashboard_repo" => repository} = params) do
    access_repository(conn, repository, "admin", fn repository ->
      members_count = Repositories.members_count(repository)

      params =
        params
        |> Map.put("token", repository.name)
        |> Map.put("quantity", members_count)

      update_billing(conn, repository, params, &Hexpm.Billing.create/1)
    end)
  end

  def new(conn, _params) do
    render_new(conn)
  end

  def create(conn, params) do
    Hexpm.Repo.transaction(fn ->
      case Repositories.create(
             conn.assigns.current_user,
             params["repository"],
             audit: audit_data(conn)
           ) do
        {:ok, repository} ->
          billing_params =
            Map.take(params, ["email", "person", "company"])
            |> Map.put_new("person", nil)
            |> Map.put_new("company", nil)
            |> Map.put("token", params["repository"]["name"])
            |> Map.put("quantity", 1)

          case Hexpm.Billing.create(billing_params) do
            {:ok, _} ->
              conn
              |> put_flash(:info, "Organization created.")
              |> redirect(to: Routes.repository_path(conn, :show, repository))

            {:error, reason} ->
              changeset = Repository.changeset(%Repository{}, params["repository"])

              conn
              |> put_status(400)
              |> put_flash(:error, "Oops, something went wrong! Please check the errors below.")
              |> render_new(
                changeset: changeset,
                params: params,
                errors: reason["errors"]
              )
              |> Hexpm.Repo.rollback()
          end

        {:error, changeset} ->
          conn
          |> put_status(400)
          |> render_new(changeset: changeset, params: params)
          |> Hexpm.Repo.rollback()
      end
    end)
    |> elem(1)
  end

  defp update_billing(conn, repository, params, fun) do
    billing_params =
      params
      |> Map.take(["email", "person", "company", "token", "quantity"])
      |> Map.put_new("person", nil)
      |> Map.put_new("company", nil)

    case fun.(billing_params) do
      {:ok, _} ->
        conn
        |> put_flash(:info, "Updated your billing information.")
        |> redirect(to: Routes.repository_path(conn, :show, repository))

      {:error, reason} ->
        conn
        |> put_status(400)
        |> put_flash(:error, "Failed to update billing information.")
        |> render_index(repository, params: params, errors: reason["errors"])
    end
  end

  defp render_new(conn, opts \\ []) do
    render(
      conn,
      "new.html",
      title: "Dashboard - Organization sign up",
      container: "container page dashboard",
      billing_email: nil,
      person: nil,
      company: nil,
      params: opts[:params],
      errors: opts[:errors],
      changeset: opts[:changeset] || create_changeset()
    )
  end

  defp render_index(conn, repository, opts \\ []) do
    billing = Hexpm.Billing.dashboard(repository.name)

    assigns = [
      title: "Dashboard - Organization",
      container: "container page dashboard",
      repository: repository,
      params: opts[:params],
      errors: opts[:errors],
      add_member_changeset: opts[:add_member_changeset] || add_member_changeset()
    ]

    assigns = Keyword.merge(assigns, billing_assigns(billing, repository))
    render(conn, "index.html", assigns)
  end

  defp billing_assigns(nil, _repository) do
    [
      billing_started?: false,
      checkout_html: nil,
      billing_email: nil,
      subscription: nil,
      monthly_cost: nil,
      amount_with_tax: nil,
      card: nil,
      invoices: nil,
      person: nil,
      company: nil
    ]
  end

  defp billing_assigns(billing, repository) do
    post_action = Routes.repository_path(Endpoint, :billing_token, repository)

    checkout_html =
      billing["checkout_html"]
      |> String.replace("${post_action}", post_action)
      |> String.replace("${csrf_token}", get_csrf_token())

    [
      billing_started?: true,
      checkout_html: checkout_html,
      billing_email: billing["email"],
      subscription: billing["subscription"],
      monthly_cost: billing["monthly_cost"],
      amount_with_tax: billing["amount_with_tax"],
      quantity: billing["quantity"],
      tax_rate: billing["tax_rate"],
      discount: billing["discount"],
      card: billing["card"],
      invoices: billing["invoices"],
      person: billing["person"],
      company: billing["company"]
    ]
  end

  defp access_repository(conn, repository, role, fun) do
    user = conn.assigns.current_user
    repository = Repositories.get(repository, [:packages, :repository_users, users: :emails])

    if repository do
      if repo_user = Enum.find(repository.repository_users, &(&1.user_id == user.id)) do
        if repo_user.role in Repository.role_or_higher(role) do
          fun.(repository)
        else
          conn
          |> put_status(400)
          |> put_flash(:error, "You do not have permission for this action.")
          |> render_index(repository)
        end
      else
        not_found(conn)
      end
    else
      not_found(conn)
    end
  end

  defp add_member_changeset() do
    Repository.add_member(%RepositoryUser{}, %{})
  end

  defp create_changeset() do
    Repository.changeset(%Repository{}, %{})
  end

  defp remove_member_error_message(:unknown_user, username), do: "Unknown user #{username}."

  defp remove_member_error_message(:last_member, _username),
    do: "Cannot remove last member from organization."
end
