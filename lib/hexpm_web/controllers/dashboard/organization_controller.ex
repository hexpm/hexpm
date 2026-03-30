defmodule HexpmWeb.Dashboard.OrganizationController do
  use HexpmWeb, :controller
  alias HexpmWeb.Dashboard.KeyController
  alias HexpmWeb.Dashboard.Organization.Components.BillingHelpers

  plug :requires_login

  plug HexpmWeb.Plugs.Sudo
       when action in [
              :new,
              :create,
              :show,
              :members,
              :keys,
              :packages,
              :billing,
              :danger_zone,
              :update,
              :audit_logs,
              :leave,
              :billing_token,
              :cancel_billing,
              :resume_billing,
              :update_billing,
              :create_billing,
              :add_seats,
              :remove_seats,
              :void_invoice,
              :change_plan,
              :create_key,
              :delete_key,
              :show_invoice,
              :pay_invoice,
              :update_profile
            ]

  def redirect_repo(conn, params) do
    glob = params["glob"] || []
    path = ~p"/dashboard/orgs" <> "/" <> Enum.join(glob, "/")

    conn
    |> put_status(301)
    |> redirect(to: path)
  end

  def show(conn, %{"dashboard_org" => organization}) do
    access_organization(conn, organization, "read", fn organization ->
      render_index(conn, organization)
    end)
  end

  def members(conn, %{"dashboard_org" => organization}) do
    access_organization(conn, organization, "read", fn organization ->
      render_index(conn, organization, tab: :members)
    end)
  end

  def keys(conn, %{"dashboard_org" => organization}) do
    access_organization(conn, organization, "write", fn organization ->
      generated_key = get_session(conn, :generated_key)
      conn = delete_session(conn, :generated_key)
      render_index(conn, organization, tab: :keys, generated_key: generated_key)
    end)
  end

  def packages(conn, %{"dashboard_org" => organization}) do
    access_organization(conn, organization, "read", fn organization ->
      render_index(conn, organization, tab: :packages)
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

      if !customer["subscription"] || customer["quantity"] > user_count do
        if user = Users.public_get(username, [:emails]) do
          case Organizations.add_member(organization, user, params, audit: audit_data(conn)) do
            {:ok, _} ->
              conn
              |> put_flash(:info, "User #{username} has been added to the organization.")
              |> redirect(to: ~p"/dashboard/orgs/#{organization}/members")

            {:error, changeset} ->
              conn
              |> put_status(400)
              |> render_index(organization, tab: :members, add_member_changeset: changeset)
          end
        else
          conn
          |> put_status(400)
          |> put_flash(:error, "Unknown user #{username}.")
          |> render_index(organization, tab: :members)
        end
      else
        conn
        |> put_status(400)
        |> put_flash(:error, "Not enough seats in organization to add member.")
        |> render_index(organization, tab: :members)
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
          |> redirect(to: ~p"/dashboard/orgs/#{organization}/members")

        {:error, :last_member} ->
          conn
          |> put_status(400)
          |> put_flash(:error, "Cannot remove last member from organization.")
          |> render_index(organization, tab: :members)
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
            |> redirect(to: ~p"/dashboard/orgs/#{organization}/members")

          {:error, :last_admin} ->
            conn
            |> put_status(400)
            |> put_flash(:error, "Cannot demote last admin member.")
            |> render_index(organization, tab: :members)

          {:error, changeset} ->
            conn
            |> put_status(400)
            |> render_index(organization, tab: :members, change_role_changeset: changeset)
        end
      else
        conn
        |> put_status(400)
        |> put_flash(:error, "Unknown user #{username}.")
        |> render_index(organization, tab: :members)
      end
    end)
  end

  def audit_logs(conn, %{"dashboard_org" => organization} = params) do
    access_organization(conn, organization, "read", fn organization ->
      per_page = 20
      page = Hexpm.Utils.safe_int(params["page"]) || 1
      audit_logs = AuditLogs.all_by(organization, page, per_page)
      count = AuditLogs.count_by(organization)

      render_index(conn, organization,
        tab: :audit_logs,
        audit_logs: audit_logs,
        audit_logs_total_count: count,
        page: page,
        per_page: per_page
      )
    end)
  end

  def billing(conn, %{"dashboard_org" => organization}) do
    access_organization(conn, organization, "admin", fn organization ->
      render_index(conn, organization, tab: :billing)
    end)
  end

  def danger_zone(conn, %{"dashboard_org" => organization}) do
    access_organization(conn, organization, "read", fn organization ->
      render_index(conn, organization, tab: :danger_zone)
    end)
  end

  def leave(conn, %{
        "dashboard_org" => organization,
        "organization_name" => organization_name
      }) do
    access_organization(conn, organization, "read", fn organization ->
      if organization.name == organization_name do
        current_user = conn.assigns.current_user

        case Organizations.remove_member(organization, current_user, audit: audit_data(conn)) do
          :ok ->
            conn
            |> put_flash(:info, "You just left the organization #{organization.name}.")
            |> redirect(to: ~p"/dashboard/profile")

          {:error, :last_member} ->
            conn
            |> put_status(400)
            |> put_flash(:error, "The last member of an organization cannot leave.")
            |> render_index(organization, tab: :danger_zone)
        end
      else
        conn
        |> put_status(400)
        |> put_flash(:error, "Invalid organization name.")
        |> render_index(organization, tab: :danger_zone)
      end
    end)
  end

  def billing_token(conn, %{"dashboard_org" => organization, "token" => token}) do
    access_organization(conn, organization, "admin", fn organization ->
      audit = %{audit_data: audit_data(conn), organization: organization}

      case Hexpm.Billing.checkout(organization.name, %{payment_source: token}, audit: audit) do
        {:ok, _} ->
          conn
          |> put_resp_header("content-type", "application/json")
          |> send_resp(200, Jason.encode!(%{}))

        {:error, reason} ->
          conn
          |> put_resp_header("content-type", "application/json")
          |> send_resp(422, Jason.encode!(reason))
      end
    end)
  end

  def cancel_billing(conn, %{"dashboard_org" => organization}) do
    access_organization(conn, organization, "admin", fn organization ->
      audit = %{audit_data: audit_data(conn), organization: organization}
      customer = Hexpm.Billing.cancel(organization.name, audit: audit)

      message = cancel_message(customer["subscription"]["current_period_end"])

      conn
      |> put_flash(:info, message)
      |> redirect(to: ~p"/dashboard/orgs/#{organization}/billing")
    end)
  end

  def resume_billing(conn, %{"dashboard_org" => organization}) do
    access_organization(conn, organization, "admin", fn organization ->
      audit = %{audit_data: audit_data(conn), organization: organization}

      case Hexpm.Billing.resume(organization.name, audit: audit) do
        {:ok, _customer} ->
          conn
          |> put_flash(:info, "Your subscription has been resumed.")
          |> redirect(to: ~p"/dashboard/orgs/#{organization}/billing")

        {:error, reason} ->
          conn
          |> put_flash(:error, reason["errors"] || "Failed to resume subscription.")
          |> redirect(to: ~p"/dashboard/orgs/#{organization}/billing")
      end
    end)
  end

  def show_invoice(conn, %{"dashboard_org" => organization, "id" => id}) do
    access_organization(conn, organization, "admin", fn organization ->
      id = safe_to_integer(id)

      if is_nil(id) do
        not_found(conn)
      else
        customer = Hexpm.Billing.get(organization.name)
        invoice_ids = Enum.map(customer["invoices"], & &1["id"])

        if id in invoice_ids do
          invoice =
            Hexpm.Billing.invoice(id, style_nonce: conn.assigns[:style_src_nonce])

          conn
          |> put_resp_header("content-type", "text/html")
          |> send_resp(200, invoice)
        else
          not_found(conn)
        end
      end
    end)
  end

  def pay_invoice(conn, %{"dashboard_org" => organization, "id" => id}) do
    access_organization(conn, organization, "admin", fn organization ->
      id = safe_to_integer(id)

      if is_nil(id) do
        not_found(conn)
      else
        customer = Hexpm.Billing.get(organization.name)
        invoice_ids = Enum.map(customer["invoices"], & &1["id"])

        audit = %{audit_data: audit_data(conn), organization: organization}

        if id in invoice_ids do
          case Hexpm.Billing.pay_invoice(id, audit: audit) do
            :ok ->
              conn
              |> put_flash(:info, "Invoice paid.")
              |> redirect(to: ~p"/dashboard/orgs/#{organization}/billing")

            {:error, reason} ->
              conn
              |> put_status(400)
              |> put_flash(:error, "Failed to pay invoice: #{reason["errors"]}.")
              |> render_index(organization, tab: :billing)
          end
        else
          not_found(conn)
        end
      end
    end)
  end

  def update_billing(conn, %{"dashboard_org" => organization} = params) do
    access_organization(conn, organization, "admin", fn organization ->
      audit = %{audit_data: audit_data(conn), organization: organization}

      update_billing(
        conn,
        organization,
        params,
        &Hexpm.Billing.update(organization.name, &1, audit: audit)
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

      audit = %{audit_data: audit_data(conn), organization: organization}

      update_billing(conn, organization, params, &Hexpm.Billing.create(&1, audit: audit))
    end)
  end

  @not_enough_seats "The number of open seats cannot be less than the number of organization members."

  def add_seats(conn, %{"dashboard_org" => organization} = params) do
    access_organization(conn, organization, "admin", fn organization ->
      current_seats = safe_to_integer(params["current-seats"])
      add_seats_val = safe_to_integer(params["add-seats"])

      if is_nil(current_seats) or is_nil(add_seats_val) do
        conn
        |> put_flash(:error, "Invalid seat numbers.")
        |> redirect(to: ~p"/dashboard/orgs/#{organization}/billing")
      else
        user_count = Organizations.user_count(organization)
        seats = current_seats + add_seats_val

        if seats >= user_count do
          audit = %{audit_data: audit_data(conn), organization: organization}

          case Hexpm.Billing.update(organization.name, %{"quantity" => seats}, audit: audit) do
            {:ok, _customer} ->
              conn
              |> put_flash(:info, "The number of open seats have been increased.")
              |> redirect(to: ~p"/dashboard/orgs/#{organization}/billing")

            {:requires_action, body} ->
              conn
              |> put_resp_content_type("application/json")
              |> send_resp(
                402,
                Jason.encode!(%{
                  requires_action: true,
                  client_secret: body["client_secret"],
                  invoice_id: body["invoice_id"],
                  stripe_publishable_key: body["stripe_publishable_key"]
                })
              )

            {:error, reason} ->
              conn
              |> put_flash(:error, reason["errors"] || "Failed to update billing information.")
              |> redirect(to: ~p"/dashboard/orgs/#{organization}/billing")
          end
        else
          conn
          |> put_status(400)
          |> put_flash(:error, @not_enough_seats)
          |> render_index(organization, tab: :billing)
        end
      end
    end)
  end

  def remove_seats(conn, %{"dashboard_org" => organization} = params) do
    access_organization(conn, organization, "admin", fn organization ->
      seats = safe_to_integer(params["seats"])

      if is_nil(seats) do
        conn
        |> put_flash(:error, "Invalid seat number.")
        |> redirect(to: ~p"/dashboard/orgs/#{organization}/billing")
      else
        user_count = Organizations.user_count(organization)

        if seats >= user_count do
          audit = %{audit_data: audit_data(conn), organization: organization}

          case Hexpm.Billing.update(organization.name, %{"quantity" => seats}, audit: audit) do
            {:ok, _customer} ->
              conn
              |> put_flash(:info, "The number of open seats have been reduced.")
              |> redirect(to: ~p"/dashboard/orgs/#{organization}/billing")

            {:error, reason} ->
              conn
              |> put_flash(:error, reason["errors"] || "Failed to update billing information.")
              |> redirect(to: ~p"/dashboard/orgs/#{organization}/billing")
          end
        else
          conn
          |> put_status(400)
          |> put_flash(:error, @not_enough_seats)
          |> render_index(organization, tab: :billing)
        end
      end
    end)
  end

  def void_invoice(conn, %{"dashboard_org" => organization, "invoice_id" => invoice_id}) do
    access_organization(conn, organization, "admin", fn organization ->
      case Hexpm.Billing.void_invoice(organization.name, invoice_id) do
        :ok -> :ok
        {:error, _reason} -> :ok
      end

      send_resp(conn, 204, "")
    end)
  end

  def change_plan(conn, %{"dashboard_org" => organization} = params) do
    access_organization(conn, organization, "admin", fn organization ->
      audit = %{audit_data: audit_data(conn), organization: organization}

      Hexpm.Billing.change_plan(
        organization.name,
        %{"plan_id" => params["plan_id"]},
        audit: audit
      )

      conn
      |> put_flash(:info, "You have switched to the #{plan_name(params["plan_id"])} plan.")
      |> redirect(to: ~p"/dashboard/orgs/#{organization}/billing")
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
        |> redirect(to: ~p"/dashboard/orgs/#{organization}")

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

    with :ok <- validate_billing_params(customer_params),
         {:ok, _} <- fun.(customer_params) do
      conn
      |> put_flash(:info, "Updated your billing information.")
      |> redirect(to: ~p"/dashboard/orgs/#{organization}/billing")
    else
      {:error, errors}
      when is_map_key(errors, "email") or
             is_map_key(errors, "person") or
             is_map_key(errors, "company") ->
        conn
        |> put_status(400)
        |> put_flash(:error, "Please fill in all required fields.")
        |> render_index(organization, params: params, errors: errors, tab: :billing)

      {:error, reason} ->
        conn
        |> put_status(400)
        |> put_flash(:error, "Failed to update billing information.")
        |> render_index(organization, params: params, errors: reason["errors"], tab: :billing)
    end
  end

  defp validate_billing_params(%{"email" => email} = params)
       when is_binary(email) and email != "" do
    person = params["person"]
    company = params["company"]

    cond do
      is_map(person) && (person["country"] == nil || person["country"] == "") ->
        {:error, %{"person" => %{"country" => ["can't be blank"]}}}

      is_map(company) ->
        errors =
          %{}
          |> maybe_add_error(company["name"] in [nil, ""], "company", "name", "can't be blank")
          |> maybe_add_error(
            company["address_country"] in [nil, ""],
            "company",
            "country",
            "can't be blank"
          )
          |> maybe_add_error(
            company["address_line1"] in [nil, ""],
            "company",
            "address",
            "can't be blank"
          )
          |> maybe_add_error(
            company["address_city"] in [nil, ""],
            "company",
            "city",
            "can't be blank"
          )
          |> maybe_add_error(
            company["address_zip"] in [nil, ""],
            "company",
            "zip_code",
            "can't be blank"
          )

        if map_size(errors) > 0, do: {:error, errors}, else: :ok

      true ->
        :ok
    end
  end

  defp validate_billing_params(_params) do
    {:error, %{"email" => ["can't be blank"]}}
  end

  defp maybe_add_error(errors, true, section, field, message) do
    put_in(errors, [Access.key(section, %{}), field], [message])
  end

  defp maybe_add_error(errors, false, _section, _field, _message), do: errors

  def create_key(conn, %{"dashboard_org" => organization} = params) do
    access_organization(conn, organization, "write", fn organization ->
      key_params = KeyController.munge_permissions(params["key"])

      case Keys.create(organization, key_params, audit: audit_data(conn)) do
        {:ok, %{key: key}} ->
          conn
          |> put_session(:generated_key, %{name: key.name, user_secret: key.user_secret})
          |> put_flash(:info, "The key #{key.name} was successfully generated.")
          |> redirect(to: ~p"/dashboard/orgs/#{organization}/keys")

        {:error, :key, changeset, _} ->
          conn
          |> put_status(400)
          |> render_index(organization, tab: :keys, key_changeset: changeset)
      end
    end)
  end

  def delete_key(conn, %{"dashboard_org" => organization, "name" => name}) do
    access_organization(conn, organization, "write", fn organization ->
      case Keys.revoke(organization, name, audit: audit_data(conn)) do
        {:ok, _struct} ->
          conn
          |> put_flash(:info, "The key #{name} was revoked successfully.")
          |> redirect(to: ~p"/dashboard/orgs/#{organization}/keys")

        {:error, _} ->
          conn
          |> put_status(400)
          |> put_flash(:error, "The key #{name} was not found.")
          |> render_index(organization, tab: :keys)
      end
    end)
  end

  def update_profile(conn, %{"dashboard_org" => organization, "profile" => profile_params}) do
    access_organization(conn, organization, "admin", fn organization ->
      case Users.update_profile(organization.user, profile_params, audit: audit_data(conn)) do
        {:ok, _updated_user} ->
          conn
          |> put_flash(:info, "Profile updated successfully.")
          |> redirect(to: ~p"/dashboard/orgs/#{organization}")

        {:error, _} ->
          conn
          |> put_status(400)
          |> put_flash(:error, "Oops, something went wrong!")
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

  defp organization_packages(%{repository: %{packages: packages}}) when is_list(packages) do
    Packages.attach_latest_releases(packages)
  end

  defp organization_packages(_), do: []

  defp render_index(conn, organization, opts \\ []) do
    user = organization.user
    public_email = user && Enum.find(user.emails, & &1.public)
    gravatar_email = user && Enum.find(user.emails, & &1.gravatar)

    customer =
      Hexpm.Billing.get(organization.name, script_nonce: conn.assigns[:script_src_nonce])

    keys = Keys.all(organization)
    per_page = opts[:per_page] || 30
    page = opts[:page] || 1
    audit_logs = opts[:audit_logs] || AuditLogs.all_by(organization, page, per_page)
    audit_logs_total_count = opts[:audit_logs_total_count] || AuditLogs.count_by(organization)
    delete_key_path = ~p"/dashboard/orgs/#{organization}/keys"
    create_key_path = ~p"/dashboard/orgs/#{organization}/keys"
    packages = organization_packages(organization)

    assigns = [
      title: "Dashboard - Organization",
      container: "container page dashboard",
      tab: opts[:tab] || :profile,
      changeset: user && User.update_profile(user, %{}),
      public_email: public_email && public_email.email,
      gravatar_email: gravatar_email && gravatar_email.email,
      organization: organization,
      repository: organization.repository,
      keys: keys,
      audit_logs: audit_logs,
      audit_logs_total_count: audit_logs_total_count,
      page: page,
      per_page: per_page,
      audit_logs_path_fn: &~p"/dashboard/orgs/#{organization}/audit-logs?#{&1}",
      params: opts[:params],
      errors: opts[:errors],
      delete_key_path: delete_key_path,
      create_key_path: create_key_path,
      generated_key: opts[:generated_key],
      key_changeset: opts[:key_changeset] || key_changeset(),
      packages: packages,
      add_member_changeset: opts[:add_member_changeset] || add_member_changeset(),
      new_organization_changeset: create_changeset()
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
      proration_amount: nil,
      proration_days: nil,
      tax_rate: nil,
      discount: nil,
      card: nil,
      invoices: [],
      person: nil,
      company: nil,
      post_action: nil,
      stripe_publishable_key: nil
    ]
  end

  defp customer_assigns(customer, organization) do
    post_action = ~p"/dashboard/orgs/#{organization}/billing-token"

    [
      billing_started?: true,
      checkout_html: customer["checkout_html"],
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
      company: customer["company"],
      post_action: post_action,
      stripe_publishable_key: customer["stripe_publishable_key"]
    ]
  end

  defp access_organization(conn, organization, role, fun) do
    user = conn.assigns.current_user

    organization =
      Organizations.get(organization, [
        :user,
        :organization_users,
        user: :emails,
        users: :emails,
        repository: [packages: :repository]
      ])

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
    Organization.add_member(%OrganizationUser{}, %{"role" => "read"})
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
    date = BillingHelpers.payment_date(cancel_date)

    "Your subscription is cancelled, you will have access to the organization until " <>
      "the end of your billing period at #{date}"
  end
end
