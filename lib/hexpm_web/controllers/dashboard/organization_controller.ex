defmodule HexpmWeb.Dashboard.OrganizationController do
  use HexpmWeb, :controller
  alias HexpmWeb.Dashboard.KeyController

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
      user_count = Organizations.user_count(organization)
      customer = Hexpm.Billing.get(organization.name)

      if customer["quantity"] > user_count do
        if user = Users.public_get(username, [:emails]) do
          case Organizations.add_member(organization, user, params, audit: audit_data(conn)) do
            {:ok, _} ->
              conn
              |> put_flash(:info, "User #{username} has been added to the organization.")
              |> redirect(to: Routes.organization_path(conn, :show, organization))

            {:error, changeset} ->
              conn
              |> put_status(400)
              |> render_index(organization, add_member: changeset)
          end
        else
          conn
          |> put_status(400)
          |> put_flash(:error, "Unknown user #{username}.")
          |> render_index(organization)
        end
      else
        conn
        |> put_status(400)
        |> put_flash(:error, "Not enough seats in organization to add member.")
        |> render_index(organization)
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
      user = Users.public_get(username)

      case Organizations.remove_member(organization, user, audit: audit_data(conn)) do
        :ok ->
          conn
          |> put_flash(:info, "User #{username} has been removed from the organization.")
          |> redirect(to: Routes.organization_path(conn, :show, organization))

        {:error, :last_member} ->
          conn
          |> put_status(400)
          |> put_flash(:error, "Cannot remove last member from organization.")
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
      if user = Users.public_get(username) do
        case Organizations.change_role(organization, user, params, audit: audit_data(conn)) do
          {:ok, _} ->
            conn
            |> put_flash(:info, "User #{username}'s role has been changed to #{params["role"]}.")
            |> redirect(to: Routes.organization_path(conn, :show, organization))

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
      else
        conn
        |> put_status(400)
        |> put_flash(:error, "Unknown user #{username}.")
        |> render_index(organization)
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
      customer = Hexpm.Billing.cancel(organization.name)
      message = cancel_message(customer["subscription"]["current_period_end"])

      conn
      |> put_flash(:info, message)
      |> redirect(to: Routes.organization_path(conn, :show, organization))
    end)
  end

  def show_invoice(conn, %{"dashboard_org" => organization, "id" => id}) do
    access_organization(conn, organization, "admin", fn organization ->
      id = String.to_integer(id)
      customer = Hexpm.Billing.get(organization.name)
      invoice_ids = Enum.map(customer["invoices"], & &1["id"])

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
      customer = Hexpm.Billing.get(organization.name)
      invoice_ids = Enum.map(customer["invoices"], & &1["id"])

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
      user_count = Organizations.user_count(organization)

      params =
        params
        |> Map.put("token", organization.name)
        |> Map.put("quantity", user_count)

      update_billing(conn, organization, params, &Hexpm.Billing.create/1)
    end)
  end

  @not_enough_seats "The number of open seats cannot be less than the number of organization members."

  def add_seats(conn, %{"dashboard_org" => organization} = params) do
    access_organization(conn, organization, "admin", fn organization ->
      user_count = Organizations.user_count(organization)
      current_seats = String.to_integer(params["current-seats"])
      add_seats = String.to_integer(params["add-seats"])
      seats = current_seats + add_seats

      if seats >= user_count do
        {:ok, _customer} = Hexpm.Billing.update(organization.name, %{"quantity" => seats})

        conn
        |> put_flash(:info, "The number of open seats have been increased.")
        |> redirect(to: Routes.organization_path(conn, :show, organization))
      else
        conn
        |> put_status(400)
        |> put_flash(:error, @not_enough_seats)
        |> render_index(organization)
      end
    end)
  end

  def remove_seats(conn, %{"dashboard_org" => organization} = params) do
    access_organization(conn, organization, "admin", fn organization ->
      user_count = Organizations.user_count(organization)
      seats = String.to_integer(params["seats"])

      if seats >= user_count do
        {:ok, _customer} = Hexpm.Billing.update(organization.name, %{"quantity" => seats})

        conn
        |> put_flash(:info, "The number of open seats have been reduced.")
        |> redirect(to: Routes.organization_path(conn, :show, organization))
      else
        conn
        |> put_status(400)
        |> put_flash(:error, @not_enough_seats)
        |> render_index(organization)
      end
    end)
  end

  def change_plan(conn, %{"dashboard_org" => organization} = params) do
    access_organization(conn, organization, "admin", fn organization ->
      Hexpm.Billing.change_plan(organization.name, %{"plan_id" => params["plan_id"]})

      conn
      |> put_flash(:info, "You have switched to the #{plan_name(params["plan_id"])} plan.")
      |> redirect(to: Routes.organization_path(conn, :show, organization))
    end)
  end

  defp plan_name("organization-monthly"), do: "monthly organization"
  defp plan_name("organization-annually"), do: "annual organization"

  def new(conn, _params) do
    render_new(conn)
  end

  def create(conn, params) do
    user = conn.assigns.current_user

    case Organizations.create(user, params["organization"], audit: audit_data(conn)) do
      {:ok, organization} ->
        conn
        |> put_flash(:info, "Organization created with one month free trial period active.")
        |> redirect(to: Routes.organization_path(conn, :show, organization))

      {:error, changeset} ->
        conn
        |> put_status(400)
        |> render_new(changeset: changeset, params: params)
    end
  end

  defp update_billing(conn, organization, params, fun) do
    customer_params =
      params
      |> Map.take(["email", "person", "company", "token", "quantity"])
      |> Map.put_new("person", nil)
      |> Map.put_new("company", nil)

    case fun.(customer_params) do
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

  def create_key(conn, %{"dashboard_org" => organization} = params) do
    access_organization(conn, organization, "write", fn organization ->
      key_params = KeyController.fixup_permissions(params["key"])

      case Keys.create(organization, key_params, audit: audit_data(conn)) do
        {:ok, %{key: key}} ->
          flash =
            "The key #{key.name} was successfully generated, " <>
              "copy the secret \"#{key.user_secret}\", you won't be able to see it again."

          conn
          |> put_flash(:info, flash)
          |> redirect(to: Routes.organization_path(conn, :show, organization))

        {:error, :key, changeset, _} ->
          conn
          |> put_status(400)
          |> render_index(organization, key_changeset: changeset)
      end
    end)
  end

  def delete_key(conn, %{"dashboard_org" => organization, "name" => name}) do
    access_organization(conn, organization, "write", fn organization ->
      case Keys.revoke(organization, name, audit: audit_data(conn)) do
        {:ok, _struct} ->
          conn
          |> put_flash(:info, "The key #{name} was revoked successfully.")
          |> redirect(to: Routes.organization_path(conn, :show, organization))

        {:error, _} ->
          conn
          |> put_status(400)
          |> put_flash(:error, "The key #{name} was not found.")
          |> render_index(organization)
      end
    end)
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
    customer = Hexpm.Billing.get(organization.name)
    keys = Keys.all(organization)
    delete_key_path = Routes.organization_path(Endpoint, :delete_key, organization)
    create_key_path = Routes.organization_path(Endpoint, :create_key, organization)

    assigns = [
      title: "Dashboard - Organization",
      container: "container page dashboard",
      organization: organization,
      repository: organization.repository,
      keys: keys,
      params: opts[:params],
      errors: opts[:errors],
      delete_key_path: delete_key_path,
      create_key_path: create_key_path,
      key_changeset: opts[:key_changeset] || key_changeset(),
      add_member_changeset: opts[:add_member_changeset] || add_member_changeset()
    ]

    assigns = Keyword.merge(assigns, customer_assigns(customer, organization))
    render(conn, "index.html", assigns)
  end

  defp customer_assigns(nil, _organization) do
    [
      billing_started?: false,
      checkout_html: nil,
      billing_email: nil,
      plan_id: "organization-monthly",
      subscription: nil,
      monthly_cost: nil,
      amount_with_tax: nil,
      quantity: nil,
      max_period_quantity: nil,
      card: nil,
      invoices: nil,
      person: nil,
      company: nil
    ]
  end

  defp customer_assigns(customer, organization) do
    post_action = Routes.organization_path(Endpoint, :billing_token, organization)

    checkout_html =
      customer["checkout_html"]
      |> String.replace("${post_action}", post_action)
      |> String.replace("${csrf_token}", get_csrf_token())

    [
      billing_started?: true,
      checkout_html: checkout_html,
      billing_email: customer["email"],
      plan_id: customer["plan_id"],
      proration_amount: customer["proration_amount"],
      proration_days: customer["proration_days"],
      subscription: customer["subscription"],
      monthly_cost: customer["monthly_cost"],
      amount_with_tax: customer["amount_with_tax"],
      quantity: customer["quantity"],
      max_period_quantity: customer["max_period_quantity"],
      tax_rate: customer["tax_rate"],
      discount: customer["discount"],
      card: customer["card"],
      invoices: customer["invoices"],
      person: customer["person"],
      company: customer["company"]
    ]
  end

  defp access_organization(conn, organization, role, fun) do
    user = conn.assigns.current_user

    organization =
      Organizations.get(organization, [:organization_users, users: :emails, repository: :packages])

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

  defp key_changeset() do
    Key.changeset(%Key{}, %{}, %{})
  end

  defp cancel_message(nil = _cancel_date) do
    "Your subscription is cancelled"
  end

  defp cancel_message(cancel_date) do
    date = HexpmWeb.Dashboard.OrganizationView.payment_date(cancel_date)

    "Your subscription is cancelled, you will have access to the organization until " <>
      "the end of your billing period at #{date}"
  end
end
