defmodule Hexpm.Accounts.OrganizationTFA do
  @moduledoc """
  Organization enrollment and session requirements. A scheduled policy requires
  enrollment for admission; its deadline determines when existing members need
  verified sessions. Membership and seat allocation are retained on suspension.
  """
  use Hexpm.Context

  alias Hexpm.Accounts.{Organization, Organizations, Seats, TFASessions}
  alias Hexpm.Accounts.SSO
  alias Hexpm.Accounts.SSO.{Enforcement, Identity}
  alias Hexpm.OAuth.Token

  @intervals [86_400, 604_800, 2_592_000]

  @doc """
  Whether an organization may enable a new 2FA policy.
  """
  def enabled?(%Organization{name: name}) do
    case config()[:mode] do
      :off -> false
      :beta -> name in config()[:beta_organizations]
      :enabled -> true
    end
  end

  def available? do
    case config()[:mode] do
      :off -> false
      :beta -> config()[:beta_organizations] != []
      :enabled -> true
    end
  end

  @doc """
  Existing policies remain manageable independently of rollout availability.
  """
  def configurable?(organization), do: enabled?(organization) or scheduled?(organization)

  defp config, do: Application.fetch_env!(:hexpm, :organization_tfa)

  @doc """
  Whether 2FA enforcement is switched on at all. `off` is the global stop:
  scheduled policies stay in place and remain manageable, but nothing is
  enforced until the mode is `beta` or `enabled` again.
  """
  def enforcement_enabled?, do: config()[:mode] != :off

  @doc """
  A scheduled policy the global switch is not holding off. Every enforcement and
  reauthorization decision goes through this rather than `scheduled?/1`, so the
  switch reaches all of them.
  """
  def active?(organization), do: enforcement_enabled?() and scheduled?(organization)

  def scheduled?(organization), do: not is_nil(organization.tfa_required_at)

  def enforced?(organization, now \\ DateTime.utc_now()) do
    active?(organization) and DateTime.compare(now, organization.tfa_required_at) != :lt
  end

  def changeset(organization, attrs, now \\ DateTime.utc_now()) do
    organization
    |> Ecto.Changeset.cast(attrs, [:tfa_required_at, :tfa_session_lifetime_seconds])
    |> Ecto.Changeset.validate_required([:tfa_session_lifetime_seconds])
    |> Ecto.Changeset.validate_inclusion(:tfa_session_lifetime_seconds, @intervals)
    |> Ecto.Changeset.validate_change(:tfa_required_at, fn :tfa_required_at, deadline ->
      cond do
        is_nil(deadline) ->
          []

        enforced?(organization, now) and deadline != organization.tfa_required_at ->
          [tfa_required_at: "disable enforcement before scheduling another transition"]

        DateTime.compare(deadline, now) == :lt ->
          [tfa_required_at: "must be now or in the future"]

        DateTime.diff(deadline, now, :microsecond) > 2_592_000_000_000 ->
          [tfa_required_at: "must be within 30 days"]

        true ->
          []
      end
    end)
  end

  def configure(organization, user, session_id, attrs, audit: audit_data) do
    Repo.transaction(fn ->
      Repo.one(
        from(c in SSO.Connection,
          where: c.organization_id == ^organization.id,
          lock: "FOR UPDATE"
        )
      )

      organization = Seats.lock!(organization)
      user = TFASessions.lock_user!(user)
      now = DateTime.utc_now()

      cond do
        not configurable?(organization) ->
          Repo.rollback(:unavailable)

        Organizations.get_role(organization, user) != "admin" ->
          Repo.rollback(:admin_required)

        not TFASessions.verified?(user, session_id, 300, now) ->
          Repo.rollback(:tfa_required)

        Enforcement.check(organization, user, nil, session_id) != :ok ->
          Repo.rollback(:sso_required)

        true ->
          :ok
      end

      changeset = changeset(organization, normalize_attrs(attrs, now), now)

      if changeset.valid? and changeset.changes == %{} do
        organization
      else
        updated =
          changeset
          |> Ecto.Changeset.put_change(:tfa_policy_updated_at, now)
          |> Ecto.Changeset.put_change(:tfa_policy_revision, organization.tfa_policy_revision + 1)
          |> Repo.update()
          |> case do
            {:ok, updated} -> updated
            {:error, changeset} -> Repo.rollback(changeset)
          end

        audit_data
        |> AuditLog.build(
          "organization.tfa.configure",
          {updated,
           %{
             required_at: updated.tfa_required_at,
             session_lifetime_seconds: updated.tfa_session_lifetime_seconds,
             policy_revision: updated.tfa_policy_revision
           }}
        )
        |> Repo.insert!()

        Hexpm.Accounts.OrganizationTFANotifications.policy_changed!(updated)
        updated
      end
    end)
  end

  defp normalize_attrs(attrs, now) do
    attrs
    |> Map.take(["tfa_session_lifetime_seconds"])
    |> Map.merge(deadline(attrs, now))
  end

  defp deadline(%{"enforcement" => "disabled"}, _now), do: %{"tfa_required_at" => nil}
  defp deadline(%{"enforcement" => "immediate"}, now), do: %{"tfa_required_at" => now}

  defp deadline(%{"enforcement" => "transition"} = attrs, now) do
    with grace_days when is_binary(grace_days) <- Map.get(attrs, "grace_days", "14"),
         {days, ""} when days in 1..30 <- Integer.parse(grace_days) do
      %{"tfa_required_at" => DateTime.add(now, days * 86_400)}
    else
      _ -> %{"tfa_required_at" => "invalid"}
    end
  end

  defp deadline(_attrs, _now), do: %{}

  def enrollment_status(organization, user, now \\ DateTime.utc_now()) do
    cond do
      User.tfa_enabled?(user) -> "enabled"
      enforced?(organization, now) -> "overdue"
      true -> "pending"
    end
  end

  def check(organization, principal, credential \\ nil, session_id \\ nil)
  def check(%Organization{id: 1}, _user, _credential, _session_id), do: :ok

  def check(%Organization{} = organization, %User{service: false} = user, credential, session_id) do
    organization = Repo.get!(Organization, organization.id)

    if enforced?(organization) and Organizations.get_role(organization, user) do
      cond do
        personal_key?(credential) ->
          {:error, :tfa_personal_key}

        TFASessions.verified?(
          user,
          session_id(credential, session_id),
          organization.tfa_session_lifetime_seconds
        ) ->
          :ok

        true ->
          {:error, :tfa_required}
      end
    else
      :ok
    end
  end

  def check(_organization, _principal, _credential, _session_id), do: :ok

  def personal_key?(%Key{}), do: true
  def personal_key?(%Token{grant_type: "client_credentials"}), do: true
  def personal_key?(_), do: false

  def session_id(%Token{user_session_id: id}, _), do: id
  def session_id(_, browser_id), do: browser_id

  def governed(%User{service: false} = user, names) do
    if enforcement_enabled?() do
      from(o in assoc(user, :organizations),
        where: o.name in ^names and not is_nil(o.tfa_required_at)
      )
      |> Repo.all()
    else
      []
    end
  end

  def governed(_, _), do: []

  def personal_key_refused(%User{service: false} = user) do
    if enforcement_enabled?() do
      now = DateTime.utc_now()
      Repo.all(from(o in assoc(user, :organizations), where: o.tfa_required_at <= ^now))
    else
      []
    end
  end

  def personal_key_refused(_), do: []

  # Admission and policy changes take the organization lock before the user
  # lock. Disabling 2FA also locks the user and checks current memberships.
  def admit(organization, user) do
    organization = Seats.lock!(organization)
    user = TFASessions.lock_user!(user)

    if active?(organization) and not User.tfa_enabled?(user),
      do: {:error, :tfa_enrollment_required},
      else: :ok
  end

  def admit(multi, organization, user) do
    Multi.run(multi, :tfa_admission, fn _repo, _ ->
      case admit(organization, user) do
        :ok -> {:ok, :eligible}
        error -> error
      end
    end)
  end

  def required_memberships(user) do
    if enforcement_enabled?() do
      Repo.all(from(o in assoc(user, :organizations), where: not is_nil(o.tfa_required_at)))
    else
      []
    end
  end

  def eligible_admin?(organization, member) do
    user = Repo.get!(User, member.user_id)
    connection = SSO.get_connection(organization)

    member.role == "admin" and is_nil(user.deactivated_at) and
      (not active?(organization) or User.tfa_enabled?(user)) and
      (not Enforcement.governed?(organization, connection, member.sso_enforcement) or
         Repo.exists?(
           from(i in Identity,
             where: i.organization_id == ^organization.id and i.user_id == ^user.id
           )
         ))
  end

  def protect_admin(organization, user) do
    members = Organizations.all_members(organization)
    removing = Enum.find(members, &(&1.user_id == user.id))

    if removing && removing.role == "admin" &&
         not Enum.any?(members, &(&1.user_id != user.id and eligible_admin?(organization, &1))),
       do: {:error, :last_admin},
       else: :ok
  end

  def protect_admin(multi, organization, user, role \\ nil) do
    Multi.run(multi, :eligible_admin, fn _repo, _ ->
      organization = Seats.lock!(organization)

      case if(role == "admin", do: :ok, else: protect_admin(organization, user)) do
        :ok -> {:ok, :eligible}
        error -> error
      end
    end)
  end

  def protect_account_removal(multi, user) do
    Multi.run(multi, :eligible_admin, fn _repo, _ ->
      organizations = Organizations.all_by_user(user) |> Enum.sort_by(& &1.id)
      organizations = Enum.map(organizations, &Seats.lock!/1)
      blocked = Enum.filter(organizations, &(protect_admin(&1, user) != :ok))
      if blocked == [], do: {:ok, :eligible}, else: {:error, {:organizations, blocked}}
    end)
  end
end
