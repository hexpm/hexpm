defmodule HexpmWeb.Plugs.OrganizationSSO do
  @moduledoc """
  Requires a current organization access session on the dashboard pages of an
  organization that enforces SSO.

  This runs alongside sudo rather than instead of it: sudo says the person at
  the keyboard is still the account holder, and the organization access session
  says the organization's provider still vouches for them. Neither answers the
  other's question.

  Pass `except:` the actions enforcement deliberately leaves open, or
  `except: :all` for a controller that is entirely carve-out. Billing and the
  SSO settings are the carve-out: an organization whose provider has broken, or
  whose administrator was deactivated in it by mistake, has to be able to repair
  the connection and keep paying, and it could not if those screens sat behind
  the gate they are the only way to unlock. Reaching one that way is audited and
  mailed to the administrators.
  """

  @behaviour Plug

  alias Hexpm.Accounts.Organizations
  alias Hexpm.Accounts.SSO.Enforcement
  alias HexpmWeb.SSOEnforcement

  @impl Plug
  def init(opts), do: Keyword.fetch!(opts, :except)

  @impl Plug
  def call(conn, except) do
    with %{} = user <- conn.assigns[:current_user],
         %{} = organization <- organization(conn),
         {:error, refusal} <- SSOEnforcement.check(conn, organization, user) do
      if carve_out?(conn, except) do
        Enforcement.break_glass(
          organization,
          user,
          Phoenix.Controller.action_name(conn),
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

  defp carve_out?(_conn, :all), do: true
  defp carve_out?(conn, except), do: Phoenix.Controller.action_name(conn) in except

  defp organization(conn) do
    case conn.params["dashboard_org"] do
      name when is_binary(name) -> Organizations.get(name)
      _ -> nil
    end
  end
end
