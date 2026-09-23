defmodule Hexpm.Accounts.OrganizationTFANotifications do
  use Hexpm.Context
  alias Hexpm.Accounts.{OrganizationTFA, OrganizationTFANotification, Organizations, Seats}
  alias Hexpm.Emails.{Outbox, OutboxEntry}

  @category "organization.tfa"
  @stages ~w(scheduled seven_days one_day suspended summary)

  def policy_changed!(organization) do
    cancel_organization!(organization)

    if OrganizationTFA.active?(organization) do
      now = DateTime.utc_now()

      organization
      |> Organizations.all_members(user: :emails)
      |> Enum.filter(&due?(organization, &1, "scheduled", now))
      |> Enum.each(&enqueue!(organization, &1, "scheduled"))
    end
  end

  def sweep(now \\ DateTime.utc_now()) do
    Repo.all(from(o in Organization, where: not is_nil(o.tfa_required_at)))
    |> Enum.each(fn organization ->
      Repo.transaction(fn ->
        organization = Seats.lock!(organization)

        if OrganizationTFA.active?(organization) do
          for member <- Organizations.all_members(organization, user: :emails),
              stage <- @stages -- ["scheduled"],
              due?(organization, member, stage, now) do
            enqueue!(organization, member, stage)
          end
        end
      end)
    end)

    :ok
  end

  def valid?(entry, now \\ DateTime.utc_now())

  def valid?(%OutboxEntry{category: @category, group_key: key}, now) do
    with ["tfa", org_id, revision, user_id, stage] <- String.split(key, ":"),
         %Organization{} = organization <- Repo.get(Organization, String.to_integer(org_id)),
         true <- organization.tfa_policy_revision == String.to_integer(revision),
         true <- OrganizationTFA.active?(organization),
         %OrganizationUser{} = member <-
           Repo.get_by(OrganizationUser,
             organization_id: organization.id,
             user_id: String.to_integer(user_id)
           ) do
      due?(organization, Repo.preload(member, :user), stage, now)
    else
      _ -> false
    end
  end

  def valid?(_entry, _now), do: true

  def cancel_member!(organization, user) do
    Repo.all(
      from(e in OutboxEntry.undelivered(),
        where: e.category == @category and e.scope_key == ^scope(organization),
        where: like(e.group_key, ^"tfa:#{organization.id}:%:#{user.id}:%")
      )
    )
    |> Enum.each(fn entry ->
      Outbox.cancel!(group_key: entry.group_key, categories: [@category])
    end)

    refresh_summaries!([organization.id])
  end

  def cancel_obsolete!(user) do
    Repo.all(
      from(e in OutboxEntry.undelivered(),
        where: e.category == @category,
        where: like(e.group_key, ^"tfa:%:%:#{user.id}:%")
      )
    )
    |> Enum.reject(&valid?/1)
    |> Enum.each(&Outbox.cancel!(group_key: &1.group_key, categories: [@category]))

    organization_ids = Organizations.all_by_user(user) |> Enum.map(& &1.id)
    refresh_summaries!(organization_ids)
    :ok
  end

  def prepare_delivery!(%OutboxEntry{category: @category, group_key: key} = entry) do
    case String.split(key, ":") do
      ["tfa", organization_id, _revision, _user_id, "summary"] ->
        refresh_summary!(entry, Repo.get!(Organization, String.to_integer(organization_id)))

      _ ->
        entry
    end
  end

  def prepare_delivery!(entry), do: entry

  defp refresh_summaries!(organization_ids) do
    scopes = Enum.map(organization_ids, &"tfa:organization:#{&1}")

    from(e in OutboxEntry.undelivered(),
      where: e.category == @category and e.scope_key in ^scopes,
      where: like(e.group_key, "tfa:%:summary"),
      order_by: e.id,
      lock: "FOR UPDATE SKIP LOCKED"
    )
    |> Repo.all()
    |> Enum.each(fn entry ->
      if valid?(entry), do: prepare_delivery!(entry)
    end)
  end

  defp refresh_summary!(entry, organization) do
    email =
      Hexpm.Emails.organization_tfa(
        organization,
        "summary",
        entry.recipients,
        suspended_members(organization)
      )

    attrs = Outbox.prepare!(email, category: @category)

    entry
    |> Ecto.Changeset.change(Map.take(attrs, [:email, :subject]))
    |> Repo.update!(log: false)
  end

  defp suspended_members(organization) do
    Organizations.all_members(organization, :user)
    |> Enum.filter(&(not User.tfa_enabled?(&1.user)))
    |> Enum.map(& &1.user.username)
  end

  defp cancel_organization!(organization),
    do: Outbox.cancel!(scope_key: scope(organization), categories: [@category])

  defp scope(organization), do: "tfa:organization:#{organization.id}"

  defp due?(organization, member, stage, now) do
    remaining = DateTime.diff(organization.tfa_required_at, now, :microsecond)

    transition =
      if organization.tfa_policy_updated_at,
        do: DateTime.diff(organization.tfa_required_at, organization.tfa_policy_updated_at),
        else: 0

    enrolled? = User.tfa_enabled?(member.user)

    case stage do
      "scheduled" ->
        not enrolled? and remaining > 0

      "seven_days" ->
        not enrolled? and transition >= 7 * 86_400 and remaining > 86_400_000_000 and
          remaining <= 604_800_000_000

      "one_day" ->
        not enrolled? and transition >= 86_400 and remaining > 0 and remaining <= 86_400_000_000

      "suspended" ->
        not enrolled? and remaining <= 0

      "summary" ->
        member.role == "admin" and remaining <= 0

      _ ->
        false
    end
  end

  defp enqueue!(organization, member, stage) do
    now = DateTime.utc_now()

    {count, _} =
      Repo.insert_all(
        OrganizationTFANotification,
        [
          %{
            organization_id: organization.id,
            revision: organization.tfa_policy_revision,
            user_id: member.user_id,
            stage: stage,
            inserted_at: now
          }
        ],
        on_conflict: :nothing,
        conflict_target: [:organization_id, :revision, :user_id, :stage]
      )

    if count == 1 do
      recipients = Hexpm.Accounts.SSO.Enforcement.user_emails(member.user)

      suspended = suspended_members(organization)

      if recipients != [] do
        Outbox.enqueue!(Hexpm.Emails.organization_tfa(organization, stage, recipients, suspended),
          category: @category,
          group_key:
            "tfa:#{organization.id}:#{organization.tfa_policy_revision}:#{member.user_id}:#{stage}",
          scope_key: scope(organization),
          expires_at:
            if(stage in ["seven_days", "one_day"],
              do: organization.tfa_required_at,
              else: Outbox.default_expires_at()
            )
        )
      end

      %{user: member.user, auth_credential: nil, user_agent: "hexpm", remote_ip: nil}
      |> AuditLog.build(
        "organization.tfa.notification",
        {organization, %{stage: stage, policy_revision: organization.tfa_policy_revision}}
      )
      |> Repo.insert!()
    end
  end
end
