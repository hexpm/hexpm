defmodule Hexpm.Accounts.OrganizationAuth do
  @moduledoc """
  Independent organization authentication requirements for human sessions.
  """
  use Hexpm.Context
  alias Hexpm.Accounts.{OrganizationTFA, TFASessions}
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
      OrganizationTFA.governed(user, names)
      |> Enum.filter(&(OrganizationTFA.check(&1, user, nil, session_id) != :ok))
      |> Enum.map(& &1.name)

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

  def personal_key_refused(user) do
    (Enforcement.personal_key_refused(user) ++ OrganizationTFA.personal_key_refused(user))
    |> Enum.uniq_by(& &1.id)
  end

  def refusal_message(refusal, organization, credential \\ nil)

  def refusal_message(:tfa_required, organization, _) do
    "2FA verification required for organization #{organization.name}. Authenticate your session again."
  end

  def refusal_message(:tfa_personal_key, organization, _) do
    "Organization #{organization.name} requires 2FA and doesn't accept personal API keys. Sign in from your Hex client or use an organization key for automation."
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
    proof = TFASessions.proof(user, session_id, now)

    tfa =
      Enum.flat_map(organizations, fn o ->
        cond do
          not OrganizationTFA.active?(o) ->
            []

          not OrganizationTFA.enforced?(o, now) ->
            [o.tfa_required_at]

          proof ->
            [
              DateTime.add(proof.tfa_verified_at, o.tfa_session_lifetime_seconds),
              proof.expires_at
            ]

          true ->
            [now]
        end
      end)

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

    source_expiry =
      if proof && proof.tfa_source_expires_at &&
           Enum.any?(organizations, &OrganizationTFA.enforced?(&1, now)),
         do: [proof.tfa_source_expires_at],
         else: []

    Enum.min_by(
      [expires_at | tfa ++ sso ++ cutoffs ++ source_expiry],
      &DateTime.to_unix(&1, :microsecond)
    )
  end

  def access_expires_at(_, _, _, expires_at, _), do: expires_at
end
