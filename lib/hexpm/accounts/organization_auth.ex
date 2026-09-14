defmodule Hexpm.Accounts.OrganizationAuth do
  @moduledoc """
  Independent organization authentication requirements for human sessions.
  """
  use Hexpm.Context
  alias Hexpm.Accounts.OrganizationTFA
  alias Hexpm.Accounts.SSO.{Enforcement, OrgSession}

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

  def access_expires_at(%User{service: false} = user, scopes, session_id, expires_at, now) do
    names =
      Enum.flat_map(scopes, fn
        "repository:" <> name -> [name]
        "docs:" <> name -> [name]
        _ -> []
      end)

    organizations = Repo.all(from(o in assoc(user, :organizations), where: o.name in ^names))

    tfa =
      if User.tfa_enabled?(user) do
        []
      else
        Enum.flat_map(organizations, fn o ->
          cond do
            not OrganizationTFA.active?(o) -> []
            OrganizationTFA.enforced?(o, now) -> [now]
            true -> [o.tfa_required_at]
          end
        end)
      end

    sso_organization_ids = Enforcement.governed(user, names) |> Enum.map(& &1.id)

    sso =
      if session_id do
        OrgSession.live(session_id, now)
        |> OrgSession.for_user(user.id)
        |> then(
          &from(s in &1,
            where: s.organization_id in ^sso_organization_ids,
            select: [
              s.expires_at,
              as(:user_session).expires_at,
              as(:sso_source_session).expires_at
            ]
          )
        )
        |> Repo.all()
        |> List.flatten()
        |> Enum.reject(&is_nil/1)
      else
        []
      end

    cutoffs =
      Enum.flat_map(organizations, fn o ->
        c = Hexpm.Accounts.SSO.get_connection(o)
        member = Repo.get_by(OrganizationUser, organization_id: o.id, user_id: user.id)

        if c && member && c.required_at && c.enforcement_mode == "required" &&
             member.sso_enforcement != "exempt" &&
             Hexpm.Accounts.SSO.Features.active?(o) && DateTime.compare(c.required_at, now) == :gt,
           do: [c.required_at],
           else: []
      end)

    Enum.min_by([expires_at | tfa ++ sso ++ cutoffs], &DateTime.to_unix(&1, :microsecond))
  end

  def access_expires_at(_, _, _, expires_at, _), do: expires_at
end
