defmodule Hexpm.Accounts.OrganizationAuth do
  @moduledoc """
  Independent organization authentication requirements for human sessions.
  """
  use Hexpm.Context
  alias Hexpm.Accounts.OrganizationTFA
  alias Hexpm.Accounts.SSO.Enforcement

  def check(organization, user, credential \\ nil, session_id \\ nil) do
    with :ok <- OrganizationTFA.check(organization, user, credential, session_id),
         :ok <- Enforcement.check(organization, user, credential, session_id),
         do: :ok
  end

  def reachable(organizations, user, credential \\ nil, session_id \\ nil) do
    Enum.filter(organizations, &(check(&1, user, credential, session_id) == :ok))
  end

  def required(user, names, session_id) do
    sso = Enforcement.sso_required(user, names, session_id)

    tfa =
      OrganizationTFA.refused(user)
      |> Enum.map(& &1.name)
      |> Enum.filter(&(&1 in names))

    (sso ++ tfa)
    |> Enum.uniq()
    |> Enum.sort()
    |> Enum.map(fn name ->
      %{
        organization: name,
        requirements:
          Enum.filter(["tfa", "sso"], fn
            "tfa" -> name in tfa
            "sso" -> name in sso
          end)
      }
    end)
  end

  def governed(user, names) do
    (Enforcement.governed(user, names) ++ OrganizationTFA.governed(user, names))
    |> Enum.uniq_by(& &1.id)
  end

  @doc """
  The organizations a personal key of this account cannot reach, with the
  refusal each one answers with.
  """
  def personal_key_refusals(user) do
    (Enum.map(Enforcement.personal_key_refused(user), &{&1, :personal_key}) ++
       Enum.map(OrganizationTFA.refused(user), &{&1, :tfa_required}))
    |> Enum.uniq_by(fn {organization, _refusal} -> organization.id end)
  end

  def refusal_message(refusal, organization, credential \\ nil)

  def refusal_message(:tfa_required, organization, _) do
    "Organization #{organization.name} requires two-factor authentication. Enable it in your account security settings."
  end

  def refusal_message(refusal, organization, credential),
    do: Enforcement.refusal_message(refusal, organization, credential)
end
