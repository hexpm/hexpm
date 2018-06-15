defmodule Hexpm.Web.Dashboard.OrganizationController do
  use Hexpm.Web, :controller

  plug :requires_login

  def redirect_repo(conn, params) do
    glob = params["glob"] || []
    path = Routes.organization_path(conn, :new) <> "/" <> Enum.join(glob, "/")

    conn
    |> put_status(301)
    |> redirect(to: path)
  end

  def show(conn, %{"dashboard_org" => organization}) do
    access_organization(conn, organization, "read", fn organization ->
      render_index(conn, organization)
    end)
  end

  def update(conn, %{
        "dashboard_org" => organization,
        "action" => "add_member",
        "organization_user" => params
      }) do
    username = params["username"]

    access_organization(conn, organization, "admin", fn organization ->
      case Organizations.add_member(organization, username, params, audit: audit_data(conn)) do
        {:ok, _} ->
          members_count = Organizations.members_count(organization)

          {:ok, _customer} =
            Hexpm.Billing.update(organization.name, %{"quantity" => members_count})

          conn
          |> put_flash(:info, "User #{username} has been added to the organization.")
          |> redirect(to: Routes.organization_path(conn, :show, organization))

        {:error, :unknown_user} ->
          conn
          |> put_status(400)
          |> put_flash(:error, "Unknown user #{username}.")
          |> render_index(organization)

        {:error, changeset} ->
          conn
          |> put_status(400)
          |> render_index(organization, add_member: changeset)
      end
    end)
  end

  def update(conn, %{
        "dashboard_org" => organization,
        "action" => "remove_member",
        "organization_user" => params
      }) do
    # TODO: Also remove all package ownerships on organization for removed member
    username = params["username"]

    access_organization(conn, organization, "admin", fn organization ->
      case Organizations.remove_member(organization, username, audit: audit_data(conn)) do
        :ok ->
          members_count = Organizations.members_count(organization)

          {:ok, _customer} =
            Hexpm.Billing.update(organization.name, %{"quantity" => members_count})

          conn
          |> put_flash(:info, "User #{username} has been removed from the organization.")
          |> redirect(to: Routes.organization_path(conn, :show, organization))

        {:error, reason} ->
          conn
          |> put_status(400)
          |> put_flash(:error, remove_member_error_message(reason, username))
          |> render_index(organization)
      end
    end)
  end

  def update(conn, %{
        "dashboard_org" => organization,
        "action" => "change_role",
        "organization_user" => params
      }) do
    username = params["username"]

    access_organization(conn, organization, "admin", fn organization ->
      case Organizations.change_role(organization, username, params, audit: audit_data(conn)) do
        {:ok, _} ->
          conn
          |> put_flash(:info, "User #{username}'s role has been changed to #{params["role"]}.")
          |> redirect(to: Routes.organization_path(conn, :show, organization))

        {:error, :unknown_user} ->
          conn
          |> put_status(400)
          |> put_flash(:error, "Unknown user #{username}.")
          |> render_index(organization)

        {:error, :last_admin} ->
          conn
          |> put_status(400)
          |> put_flash(:error, "Cannot demote last admin member.")
          |> render_index(organization)

        {:error, changeset} ->
          conn
          |> put_status(400)
          |> render_index(organization, change_role: changeset)
      end
    end)
  end

  def billing_token(conn, %{"dashboard_org" => organization, "token" => token}) do
    access_organization(conn, organization, "admin", fn organization ->
      case Hexpm.Billing.checkout(organization.name, %{payment_source: token}) do
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

  def cancel_billing(conn, %{"dashboard_org" => organization}) do
    access_organization(conn, organization, "admin", fn organization ->
      billing = Hexpm.Billing.cancel(organization.name)

      cancel_date =
        billing["subscription"]["current_period_end"]
        |> Hexpm.Web.Dashboard.OrganizationView.payment_date()

      message =
        "Your subscription is cancelled, you will have access to the organization until " <>
          "the end of your billing period at #{cancel_date}"

      conn
      |> put_flash(:info, message)
      |> redirect(to: Routes.organization_path(conn, :show, organization))
    end)
  end

  def show_invoice(conn, %{"dashboard_org" => organization, "id" => id}) do
    access_organization(conn, organization, "admin", fn organization ->
      id = String.to_integer(id)
      billing = Hexpm.Billing.dashboard(organization.name)
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

  def pay_invoice(conn, %{"dashboard_org" => organization, "id" => id}) do
    access_organization(conn, organization, "admin", fn organization ->
      id = String.to_integer(id)
      billing = Hexpm.Billing.dashboard(organization.name)
      invoice_ids = Enum.map(billing["invoices"], & &1["id"])

      if id in invoice_ids do
        case Hexpm.Billing.pay_invoice(id) do
          :ok ->
            conn
            |> put_flash(:info, "Invoice paid.")
            |> redirect(to: Routes.organization_path(conn, :show, organization))

          {:error, reason} ->
            conn
            |> put_status(400)
            |> put_flash(:error, "Failed to pay invoice: #{reason["errors"]}.")
            |> render_index(organization)
        end
      else
        not_found(conn)
      end
    end)
  end

  def update_billing(conn, %{"dashboard_org" => organization} = params) do
    access_organization(conn, organization, "admin", fn organization ->
      update_billing(
        conn,
        organization,
        params,
        &Hexpm.Billing.update(organization.name, &1)
      )
    end)
  end

  def create_billing(conn, %{"dashboard_org" => organization} = params) do
    access_organization(conn, organization, "admin", fn organization ->
      members_count = Organizations.members_count(organization)

      params =
        params
        |> Map.put("token", organization.name)
        |> Map.put("quantity", members_count)

      update_billing(conn, organization, params, &Hexpm.Billing.create/1)
    end)
  end

  def new(conn, _params) do
    render_new(conn)
  end

  def create(conn, params) do
    Hexpm.Repo.transaction(fn ->
      case Organizations.create(
             conn.assigns.current_user,
             params["organization"],
             audit: audit_data(conn)
           ) do
        {:ok, organization} ->
          billing_params =
            Map.take(params, ["email", "person", "company"])
            |> Map.put_new("person", nil)
            |> Map.put_new("company", nil)
            |> Map.put("token", params["organization"]["name"])
            |> Map.put("quantity", 1)

          case Hexpm.Billing.create(billing_params) do
            {:ok, _} ->
              conn
              |> put_flash(:info, "Organization created.")
              |> redirect(to: Routes.organization_path(conn, :show, organization))

            {:error, reason} ->
              changeset = Organization.changeset(%Organization{}, params["organization"])

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

  defp update_billing(conn, organization, params, fun) do
    billing_params =
      params
      |> Map.take(["email", "person", "company", "token", "quantity"])
      |> Map.put_new("person", nil)
      |> Map.put_new("company", nil)

    case fun.(billing_params) do
      {:ok, _} ->
        conn
        |> put_flash(:info, "Updated your billing information.")
        |> redirect(to: Routes.organization_path(conn, :show, organization))

      {:error, reason} ->
        conn
        |> put_status(400)
        |> put_flash(:error, "Failed to update billing information.")
        |> render_index(organization, params: params, errors: reason["errors"])
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

  defp render_index(conn, organization, opts \\ []) do
    billing = Hexpm.Billing.dashboard(organization.name)

    assigns = [
      title: "Dashboard - Organization",
      container: "container page dashboard",
      organization: organization,
      params: opts[:params],
      errors: opts[:errors],
      add_member_changeset: opts[:add_member_changeset] || add_member_changeset()
    ]

    assigns = Keyword.merge(assigns, billing_assigns(billing, organization))
    render(conn, "index.html", assigns)
  end

  defp billing_assigns(nil, _organization) do
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

  defp billing_assigns(billing, organization) do
    post_action = Routes.organization_path(Endpoint, :billing_token, organization)

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

  defp access_organization(conn, organization, role, fun) do
    user = conn.assigns.current_user

    organization =
      Organizations.get(organization, [:packages, :organization_users, users: :emails])

    if organization do
      if repo_user = Enum.find(organization.organization_users, &(&1.user_id == user.id)) do
        if repo_user.role in Organization.role_or_higher(role) do
          fun.(organization)
        else
          conn
          |> put_status(400)
          |> put_flash(:error, "You do not have permission for this action.")
          |> render_index(organization)
        end
      else
        not_found(conn)
      end
    else
      not_found(conn)
    end
  end

  defp add_member_changeset() do
    Organization.add_member(%OrganizationUser{}, %{})
  end

  defp create_changeset() do
    Organization.changeset(%Organization{}, %{})
  end

  defp remove_member_error_message(:unknown_user, username), do: "Unknown user #{username}."

  defp remove_member_error_message(:last_member, _username),
    do: "Cannot remove last member from organization."
end
