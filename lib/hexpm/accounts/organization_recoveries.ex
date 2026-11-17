defmodule Hexpm.Accounts.OrganizationRecoveries do
  @moduledoc """
  Recovery of an organization whose only administrator lost their account.

  A moderator starts a recovery for an account the requester signed up with.
  The organization's billing address gets a link, and the billing service
  charges the saved card a small amount with a code in the statement
  descriptor, refunded once the code is entered or expires. Following the
  link while signed in as that account and entering the code proves both the
  billing address and the payment method.

  The members and the old administrator are then told, and once the notice
  period has passed `complete/2` makes the account an administrator and
  removes the old administrator. A moderator cancels a recovery somebody
  objects to.
  """

  use Hexpm.Context

  require Logger

  alias Hexpm.Accounts.{
    AuditLogs,
    OrganizationRecovery,
    OrganizationTFA,
    Organizations,
    Seats,
    SSO,
    Users
  }

  alias Hexpm.Billing
  alias Hexpm.Emails.Outbox

  @lifetime_days 30
  @notice_days 14
  @mail_category "organization.recovery"

  def notice_days, do: @notice_days

  @doc "The recovery of `organization` that is neither completed nor canceled."
  def get_open(organization) do
    Repo.one(
      from(recovery in open_query(),
        where: recovery.organization_id == ^organization.id,
        preload: [:organization, :user, :old_admin]
      )
    )
  end

  @doc """
  Looks a recovery up by the token from the billing email. Returns nil for a
  token that is unknown, canceled, completed, or expired before the payment
  was verified, so a caller can't tell those apart.
  """
  def get_by_token(raw_token) when is_binary(raw_token) do
    now = DateTime.utc_now()

    Repo.one(
      from(recovery in open_query(),
        where: recovery.token_hash == ^hash(raw_token),
        where: not is_nil(recovery.verified_at) or recovery.expires_at > ^now,
        preload: [:organization, :user]
      )
    )
  end

  def get_by_token(_raw_token), do: nil

  @doc """
  Starts a recovery that makes `user` an administrator of `organization`.

  Refused unless the organization has at most one administrator, isn't
  managed by single sign-on, and has a billing email and a card to verify.
  """
  def start(organization, user, started_by) do
    with :ok <- check_user(organization, user),
         :ok <- check_organization(organization),
         {:ok, old_admin} <- sole_admin(organization, user),
         :ok <- check_no_open_recovery(organization),
         {:ok, billing_email} <- billing_email(organization),
         {:ok, card} <- create_payment_verification(organization) do
      raw_token = random_token()

      Multi.new()
      |> Multi.insert(
        :recovery,
        OrganizationRecovery.changeset(%OrganizationRecovery{}, %{
          organization_id: organization.id,
          user_id: user.id,
          old_admin_id: old_admin && old_admin.id,
          started_by_user_id: started_by && started_by.id,
          billing_email: billing_email,
          card_brand: card["brand"],
          card_last4: card["last4"],
          token_hash: hash(raw_token),
          expires_at: DateTime.add(DateTime.utc_now(), @lifetime_days, :day)
        })
      )
      |> Multi.run(:email, fn _repo, %{recovery: recovery} ->
        recovery = %{recovery | raw_token: raw_token, organization: organization, user: user}

        recovery
        |> Emails.organization_recovery_verification()
        |> enqueue(recovery)

        {:ok, recovery}
      end)
      |> Repo.transaction()
      |> case do
        {:ok, %{email: recovery}} -> {:ok, recovery}
        {:error, :recovery, %Ecto.Changeset{}, _changes} -> {:error, :recovery_in_progress}
      end
    end
  end

  defp check_user(organization, user) do
    cond do
      User.organization?(user) -> {:error, :user_is_organization}
      not User.verified_primary_email?(user) -> {:error, :unverified_primary_email}
      Organizations.get_role(organization, user) == "admin" -> {:error, :already_admin}
      true -> admit(organization, user)
    end
  end

  defp admit(organization, user) do
    if OrganizationTFA.active?(organization) and not User.tfa_enabled?(user),
      do: {:error, :tfa_enrollment_required},
      else: :ok
  end

  # An organization behind single sign-on gets its administrators from the
  # identity provider, not from a recovery.
  defp check_organization(organization) do
    if SSO.get_connection(organization), do: {:error, :sso_connection}, else: :ok
  end

  defp sole_admin(organization, user) do
    admins =
      organization
      |> Organizations.all_members([:user])
      |> Enum.filter(&(&1.role == "admin" and &1.user_id != user.id))

    case admins do
      [] -> {:ok, nil}
      [admin] -> {:ok, admin.user}
      _admins -> {:error, :other_admins}
    end
  end

  defp check_no_open_recovery(organization) do
    if get_open(organization), do: {:error, :recovery_in_progress}, else: :ok
  end

  defp billing_email(organization) do
    case Billing.get(organization.name) do
      %{"email" => email} when is_binary(email) and email != "" -> {:ok, email}
      _billing -> {:error, :no_billing}
    end
  end

  defp create_payment_verification(organization) do
    case Billing.create_payment_verification(organization.name) do
      {:ok, card} ->
        {:ok, card}

      {:error, %{"errors" => %{"payment_verification" => reason}}} ->
        {:error, {:payment_verification, reason}}

      {:error, _body} ->
        {:error, :billing_unavailable}
    end
  end

  @doc """
  Checks the statement code `user` entered for `recovery` and, when it
  matches, starts the notice period and tells the members and the old
  administrator.
  """
  def verify(%OrganizationRecovery{user_id: user_id}, %User{id: id}, _code)
      when user_id != id do
    {:error, :wrong_user}
  end

  def verify(%OrganizationRecovery{verified_at: %DateTime{}}, _user, _code) do
    {:error, :already_verified}
  end

  def verify(%OrganizationRecovery{} = recovery, user, code) when is_binary(code) do
    case Billing.verify_payment(recovery.organization.name, code) do
      :ok -> start_notice(recovery, user)
      {:error, %{"errors" => %{"code" => reason}}} -> {:error, {:code, reason}}
      {:error, _body} -> {:error, :billing_unavailable}
    end
  end

  def verify(%OrganizationRecovery{}, _user, _code), do: {:error, {:code, "invalid"}}

  # The billing service spends the code, so a recovery that was canceled while
  # the code was being checked stays canceled.
  defp start_notice(recovery, user) do
    now = DateTime.utc_now()
    completes_at = DateTime.add(now, @notice_days, :day)

    Repo.transaction(fn ->
      locked = lock!(recovery)

      if OrganizationRecovery.open?(locked) and is_nil(locked.verified_at) do
        verified =
          locked
          |> OrganizationRecovery.verify_changeset(now, completes_at)
          |> Repo.update!()
          |> Repo.preload([:organization, :old_admin])

        verified = %{verified | user: user}

        verified
        |> Emails.organization_recovery_notice(notice_recipients(verified))
        |> enqueue(verified)

        verified
      else
        Repo.rollback(:recovery_unavailable)
      end
    end)
  end

  @doc "The verified recoveries whose notice period has passed."
  def all_due(now \\ DateTime.utc_now()) do
    Repo.all(
      from(recovery in open_query(),
        where: recovery.completes_at <= ^now,
        order_by: recovery.completes_at,
        preload: [:organization]
      )
    )
  end

  @doc """
  Completes every recovery whose notice period has passed.

  A recovery whose organization got another administrator or a single sign-on
  connection during the notice period is canceled, since the organization can
  manage its administrators again. Any other failure is reported and the
  recovery is tried again on the next run.
  """
  def run(now \\ DateTime.utc_now()) do
    now
    |> all_due()
    |> Enum.map(fn recovery ->
      organization = recovery.organization
      audit = AuditLogs.system(organization)

      case Hexpm.AdminTasks.complete_organization_recovery(organization.name, audit: audit) do
        :ok ->
          {organization.name, :ok}

        {:error, reason} when reason in [:other_admins, :sso_connection] ->
          Hexpm.AdminTasks.cancel_organization_recovery(organization.name, audit: audit)
          report(:warning, "Organization recovery canceled", organization, reason)
          {organization.name, {:canceled, reason}}

        {:error, reason} ->
          report(:error, "Organization recovery failed", organization, reason)
          {organization.name, {:error, reason}}
      end
    end)
  end

  defp report(level, message, organization, reason) do
    extra = %{organization: organization.name, reason: inspect(reason)}
    Logger.log(level, Map.merge(%{message: message, event: "organization_recovery"}, extra))
    Sentry.capture_message(message, level: level, extra: extra)
  end

  @doc """
  Makes the recovering account an administrator and removes the old
  administrator, once the notice period has passed.

  Everything happens in one transaction under the recovery's lock, so a cancel
  either lands first or finds the recovery completed. The organization is
  checked again, and the recovery waits if another administrator or a single
  sign-on connection appeared during the notice period.
  """
  def complete(%OrganizationRecovery{} = recovery, audit: audit_data) do
    now = DateTime.utc_now()

    Repo.transaction(fn ->
      locked = recovery |> lock!() |> Repo.preload([:organization, :user, :old_admin])

      cond do
        not OrganizationRecovery.open?(locked) or is_nil(locked.completes_at) ->
          Repo.rollback(:recovery_unavailable)

        DateTime.compare(locked.completes_at, now) == :gt ->
          Repo.rollback(:notice_period)

        true ->
          promote(locked, now, audit_data)
      end
    end)
    |> case do
      {:ok, :ok} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  # Removing the old administrator runs its own multi, which joins this
  # transaction. It can only succeed once the new administrator exists, and a
  # failure aborts the promotion with it.
  defp promote(recovery, now, audit_data) do
    organization = Seats.lock!(recovery.organization)
    user = recovery.user

    with :ok <- check_organization(organization),
         :ok <- check_admins(organization, recovery),
         :ok <- OrganizationTFA.admit(organization, user),
         :ok <- add_admin(organization, user, recovery.old_admin, audit_data),
         :ok <- remove_old_admin(organization, recovery.old_admin, audit_data) do
      recovery
      |> OrganizationRecovery.complete_changeset(now)
      |> Repo.update!()

      recovery
      |> Emails.organization_recovery_completed(completed_recipients(recovery))
      |> enqueue(recovery)

      :ok
    else
      {:error, reason} -> Repo.rollback(reason)
    end
  end

  defp check_admins(organization, recovery) do
    allowed = [recovery.user_id, recovery.old_admin_id]

    others =
      organization
      |> Organizations.all_members()
      |> Enum.filter(&(&1.role == "admin" and &1.user_id not in allowed))

    if others == [], do: :ok, else: {:error, :other_admins}
  end

  defp add_admin(organization, user, old_admin, audit_data) do
    case Repo.get_by(assoc(organization, :organization_users), user_id: user.id) do
      nil ->
        with {:ok, _usage} <-
               Seats.claim(organization, count: seats_needed(organization, old_admin)) do
          %OrganizationUser{organization_id: organization.id, user_id: user.id}
          |> Organization.add_member(%{"role" => "admin"})
          |> Repo.insert!()

          Repo.insert!(audit(audit_data, "organization.member.add", {organization, user}))
          :ok
        end

      member ->
        member
        |> Organization.change_role(%{"role" => "admin"})
        |> Repo.update!()

        Repo.insert!(audit(audit_data, "organization.member.role", {organization, user, "admin"}))
        :ok
    end
  end

  # The old administrator's seat is given up in the same transaction, so
  # swapping one administrator for another takes no seat.
  defp seats_needed(organization, %User{id: id}) do
    if Repo.get_by(assoc(organization, :organization_users), user_id: id), do: 0, else: 1
  end

  defp seats_needed(_organization, nil), do: 1

  defp remove_old_admin(_organization, nil, _audit_data), do: :ok

  defp remove_old_admin(organization, old_admin, audit_data),
    do: Organizations.remove_member(organization, old_admin, audit: audit_data)

  @doc "Cancels the open recovery of `organization`."
  def cancel(organization) do
    case get_open(organization) do
      nil ->
        {:error, :no_recovery}

      recovery ->
        Repo.transaction(fn ->
          locked = lock!(recovery)

          if OrganizationRecovery.open?(locked) do
            locked
            |> OrganizationRecovery.cancel_changeset(DateTime.utc_now())
            |> Repo.update!()

            Outbox.cancel!(group_key: mail_group_key(locked), categories: [@mail_category])

            :ok
          else
            Repo.rollback(:no_recovery)
          end
        end)
        |> case do
          {:ok, :ok} -> :ok
          {:error, reason} -> {:error, reason}
        end
    end
  end

  # Every member, and every verified address of the old administrator rather
  # than only the primary one, since an administrator who lost their account
  # may still read one of the others.
  defp notice_recipients(recovery) do
    members =
      recovery.organization
      |> Organizations.all_members(user: :emails)
      |> Enum.map(& &1.user)
      |> Enum.reject(&(&1.id == recovery.user_id))

    members ++ old_admin_addresses(recovery)
  end

  defp completed_recipients(recovery) do
    [Users.get_by_id(recovery.user_id, [:emails]) | old_admin_addresses(recovery)]
  end

  defp old_admin_addresses(%OrganizationRecovery{old_admin_id: nil}), do: []

  defp old_admin_addresses(%OrganizationRecovery{old_admin_id: id}) do
    Repo.all(
      from(email in Email,
        where: email.user_id == ^id and email.verified,
        preload: :user
      )
    )
  end

  # One group per recovery, so its mails go out in the order they were queued.
  defp enqueue(email, recovery) do
    Outbox.enqueue!(email,
      category: @mail_category,
      group_key: mail_group_key(recovery),
      scope_key: "organization:#{recovery.organization_id}"
    )
  end

  defp mail_group_key(recovery), do: "organization-recovery:#{recovery.id}"

  defp open_query() do
    from(recovery in OrganizationRecovery,
      where: is_nil(recovery.completed_at) and is_nil(recovery.canceled_at)
    )
  end

  defp lock!(recovery) do
    Repo.one!(
      from(row in OrganizationRecovery, where: row.id == ^recovery.id, lock: "FOR UPDATE")
    )
  end

  defp random_token, do: :crypto.strong_rand_bytes(32) |> Base.url_encode64(padding: false)

  defp hash(value), do: :crypto.hash(:sha256, value)
end

defmodule Hexpm.Accounts.OrganizationRecoveries.Worker do
  use Oban.Worker,
    queue: :periodic,
    max_attempts: 3,
    unique: [period: :infinity, states: :incomplete]

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    if Hexpm.Repo.write_mode?(), do: Hexpm.Accounts.OrganizationRecoveries.run()
    :ok
  end
end
