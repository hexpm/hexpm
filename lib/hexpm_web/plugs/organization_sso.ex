defmodule HexpmWeb.Plugs.OrganizationSSO do
  @moduledoc """
  Requires a current organization access session on pages of an organization
  that enforces SSO.

  This runs alongside sudo rather than instead of it: sudo says the person at
  the keyboard is still the account holder, and the organization access session
  says the organization's provider still vouches for them. Neither answers the
  other's question.

  `organization:` says where the organization comes from: `:dashboard_org` reads
  the route parameter, `:repository` the repository a controller has already
  resolved and assigned, and `:billing_proxy` the customer the proxied billing
  path names.

  Pass `except:` the actions enforcement deliberately leaves open. Billing, the
  SSO settings and leaving are the carve-out: an organization whose provider has
  broken, or whose administrator was deactivated in it by mistake, has to be
  able to repair the connection, keep paying, and get out, and it could not if
  those screens sat behind the gate they are the only way to unlock. Reaching
  one that way is audited and mailed to the administrators.

  `screen:` names what the audit entry records where the action name is not the
  screen a person would recognise. It defaults to the action name.
  """

  @behaviour Plug

  alias Hexpm.Accounts.Organizations
  alias Hexpm.Accounts.SSO.Enforcement
  alias HexpmWeb.SSOEnforcement

  @impl Plug
  def init(opts) do
    %{
      source: Keyword.get(opts, :organization, :dashboard_org),
      except: Keyword.get(opts, :except, []),
      screen: Keyword.get(opts, :screen)
    }
  end

  @impl Plug
  def call(conn, opts) do
    with %{} = user <- conn.assigns[:current_user],
         %{} = organization <- organization(conn, opts.source),
         {:error, refusal} <- SSOEnforcement.check(conn, organization, user) do
      if carve_out?(conn, opts.except) do
        Enforcement.break_glass(
          organization,
          user,
          screen(conn, opts.screen),
          HexpmWeb.ControllerHelpers.audit_data(conn)
        )

        conn
      else
        SSOEnforcement.refuse(conn, refusal, organization)
      end
    else
      _ -> conn
    end
  end

  defp carve_out?(conn, except), do: Phoenix.Controller.action_name(conn) in except

  defp screen(conn, nil), do: Phoenix.Controller.action_name(conn)
  defp screen(_conn, screen), do: screen

  defp organization(conn, :dashboard_org) do
    case conn.params["dashboard_org"] do
      name when is_binary(name) -> Organizations.get(name)
      _ -> nil
    end
  end

  defp organization(conn, :repository), do: conn.assigns.repository.organization

  defp organization(conn, :billing_proxy) do
    case conn.params["path"] do
      ["api", "customers", name, _action] when is_binary(name) -> Organizations.get(name)
      _ -> nil
    end
  end
end
