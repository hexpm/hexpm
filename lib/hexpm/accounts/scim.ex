defmodule Hexpm.Accounts.SCIM do
  @moduledoc """
  The SCIM Users resource: what the provider's provisioning agent reads and
  writes through `/scim/v2/Users`.

  Assignment creates membership when a verified email names an existing
  account, and a pending invitation otherwise; deactivation removes the
  membership or revokes the invitation. The resource rows are handles, not
  state: whether a person is a member is derived from `organization_users` on
  every read, so membership changed by hand shows up on the provider's next
  request. SCIM writes membership but never owns it.

  Every write acts as the organization itself in the audit log, through the
  same `organization.member.*` and `organization.invitation.*` actions the
  dashboard writes.
  """

  use Hexpm.Context

  alias Hexpm.Accounts.OrganizationTFA
  alias Hexpm.Accounts.SCIM.Resource
  alias Hexpm.Accounts.SSO
  alias Hexpm.Accounts.SSO.{Connection, Identity}

  @user_urn_prefix "urn:ietf:params:scim:schemas:core:2.0:user:"

  # Each operation can rename, which invites, and each invitation mails. The
  # providers send one or two per request; a list long enough to matter is a
  # mistake or a mail amplifier.
  @max_operations 20

  def max_operations, do: @max_operations

  @type resolved :: %{
          resource: Resource.t(),
          state: :member | :invited | :inactive,
          user: User.t() | nil
        }

  @doc """
  The listing the provider's import reads: every current member, materialized
  into a resource row on first sight, plus the rows in invited or inactive
  states. `start_index` is SCIM's 1-based offset.
  """
  def list_users(%Connection{} = connection, start_index, count, audit: audit_data) do
    materialize_members(connection, audit_data)

    total = Repo.aggregate(resources_query(connection), :count)

    page =
      from(resource in resources_query(connection),
        order_by: resource.id,
        offset: ^(start_index - 1),
        limit: ^count
      )
      |> Repo.all()
      |> Repo.preload([:user, :invitation])

    members = member_ids(connection.organization_id, page)
    resources = Enum.map(page, &resolve(&1, members))

    %{total: total, start_index: start_index, resources: resources}
  end

  # One membership query for the page rather than one per row.
  defp member_ids(organization_id, resources) do
    user_ids = for %Resource{user_id: user_id} <- resources, user_id, do: user_id

    from(organization_user in OrganizationUser,
      where: organization_user.organization_id == ^organization_id,
      where: organization_user.user_id in ^user_ids,
      select: organization_user.user_id
    )
    |> Repo.all()
    |> MapSet.new()
  end

  @doc """
  The provider's match key. A row wins; otherwise a current member whose
  verified email this is gets a row materialized, which is how people who
  joined before provisioning was turned on are matched by an import.
  """
  def find_by_user_name(%Connection{} = connection, user_name, audit: audit_data)
      when is_binary(user_name) do
    user_name = Resource.normalize_user_name(user_name)

    # Nothing that is not an address within the column's bound is stored, so
    # nothing else can match.
    if Resource.email_shaped?(user_name) do
      case get_resource_by_user_name(connection, user_name) do
        %Resource{} = resource ->
          resolve(resource)

        nil ->
          case resolve_account(connection.id, connection.organization_id, user_name) do
            %User{} = user ->
              if member?(connection.organization_id, user.id) do
                materialize_member(connection, user, user_name, audit_data)
              end

            nil ->
              nil
          end
      end
    end
  end

  # Entra maps `externalId` from `mailNickname` by default, which repeats after
  # a rehire, so two rows under one id is a shape the provider produces without
  # malice. The oldest wins rather than the request failing.
  def find_by_external_id(%Connection{}, external_id)
      when is_binary(external_id) and byte_size(external_id) > 1_024,
      do: nil

  def find_by_external_id(%Connection{} = connection, external_id)
      when is_binary(external_id) do
    case Repo.one(
           from(resource in resources_query(connection),
             where: resource.external_id == ^external_id,
             order_by: resource.id,
             limit: 1
           )
         ) do
      %Resource{} = resource -> resolve(resource)
      nil -> nil
    end
  end

  def get_user(%Connection{} = connection, scim_id) do
    with {:ok, uuid} <- Ecto.UUID.cast(scim_id),
         %Resource{} = resource <-
           Repo.one(
             from(resource in resources_query(connection), where: resource.scim_id == ^uuid)
           ) do
      {:ok, resolve(resource)}
    else
      _missing -> {:error, :not_found}
    end
  end

  @doc """
  Creates the resource, and the membership or invitation behind it unless the
  payload arrives deactivated. A duplicate `userName` is the provider's signal
  to fall back to filtering and patching, so it fails rather than adopting.
  """
  def create_user(%Connection{} = connection, params, audit: audit_data) do
    with {:ok, user_name} <- validate_user_name(params["userName"]),
         {:ok, active} <- active_value(params["active"]) do
      external_id = optional_string(params["externalId"])

      write(connection, fn ->
        cond do
          get_resource_by_user_name(connection, user_name) ->
            {:error, :uniqueness}

          active == false ->
            insert_resource(
              connection,
              %{user_name: user_name, external_id: external_id},
              audit_data
            )

          true ->
            create_active(connection, user_name, external_id, audit_data)
        end
      end)
    end
  end

  @doc """
  Full replace of the attributes we own: `userName`, `externalId`, and the
  `active` transition. Everything else in the payload is ignored.
  """
  def replace_user(%Connection{} = connection, scim_id, params, audit: audit_data) do
    with {:ok, user_name} <- validate_user_name(params["userName"]),
         {:ok, active} <- active_value(params["active"]) do
      changes = %{
        user_name: user_name,
        external_id: optional_string(params["externalId"])
      }

      changes = if active == :unchanged, do: changes, else: Map.put(changes, :active, active)

      write(connection, fn ->
        with {:ok, resolved} <- get_user(connection, scim_id) do
          apply_changes(connection, resolved, changes, audit_data)
        end
      end)
    end
  end

  @doc """
  The minimal patch set the providers use: replace or add on `active`,
  `userName`, and `externalId`, with Entra's string booleans normalized.
  Operations on attributes we do not store are ignored.
  """
  def patch_user(%Connection{}, _scim_id, operations, _opts)
      when is_list(operations) and length(operations) > @max_operations do
    {:error, :too_many_operations}
  end

  def patch_user(%Connection{} = connection, scim_id, operations, audit: audit_data)
      when is_list(operations) do
    # Every operation is parsed before any runs, so a malformed one refuses
    # the request without a transaction.
    with {:ok, changes} <- patch_changes(operations) do
      write(connection, fn ->
        with {:ok, resolved} <- get_user(connection, scim_id) do
          # Operations run one at a time, in array order, as RFC 7644
          # requires: `active` then `userName` means activate the account this
          # name matches now and relabel afterwards, which is not the same as
          # activating under the final name.
          Enum.reduce_while(changes, {:ok, resolved}, fn change, {:ok, resolved} ->
            case apply_changes(connection, resolved, change, audit_data) do
              {:ok, resolved} -> {:cont, {:ok, resolved}}
              {:error, reason} -> {:halt, {:error, reason}}
            end
          end)
        end
      end)
    end
  end

  def patch_user(%Connection{}, _scim_id, _operations, _opts), do: {:error, :invalid_path}

  @doc """
  Deactivates, then deletes the handle, freeing the `userName` slot. Sent by
  Entra on permanent deletion; Okta deactivates instead.
  """
  def delete_user(%Connection{} = connection, scim_id, audit: audit_data) do
    write(connection, fn ->
      with {:ok, resolved} <- get_user(connection, scim_id),
           {:ok, resolved} <- deactivate(connection, resolved, audit_data) do
        Repo.delete!(resolved.resource)
        audit!(audit_data, "sso.scim.resource.delete", connection, resolved.resource)
        {:ok, :deleted}
      end
    end)
    |> case do
      {:ok, :deleted} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Puts an invitation acceptance behind the same lock as the provider's writes,
  as the first step of its Multi. Acceptance goes on to lock the invitation,
  the organization seat row, and the handle it binds, all of which a
  provisioning write can hold in the other order; taking the connection first
  on both sides is what keeps the two from waiting on each other. An
  organization with no connection has nothing to lock.
  """
  def lock_provisioning(multi, %Organization{id: organization_id}) do
    Multi.run(multi, :provisioning_lock, fn _repo, _changes ->
      {:ok,
       Repo.one(
         from(row in Connection,
           where: row.organization_id == ^organization_id,
           lock: "FOR NO KEY UPDATE"
         )
       )}
    end)
  end

  @doc """
  Binds the handle behind an accepted invitation to the account that accepted
  it, in the acceptance's own transaction. Runs under the connection and
  invitation locks, so a deactivation of the same handle sees either the
  pending invitation or the member it produced, never the gap between.

  The provider's own handle wins over a row an import materialized for the
  same account under another address: that row loses its account and reads
  inactive from then on.
  """
  def adopt_acceptance(%OrganizationInvitation{id: invitation_id}, %User{id: user_id}) do
    case Repo.get_by(Resource, invitation_id: invitation_id) do
      nil ->
        {:ok, :none}

      %Resource{user_id: ^user_id} ->
        {:ok, :bound}

      %Resource{} = resource ->
        from(other in Resource,
          where: other.connection_id == ^resource.connection_id,
          where: other.user_id == ^user_id,
          where: other.id != ^resource.id
        )
        |> Repo.update_all(set: [user_id: nil])

        resource
        |> change(user_id: user_id)
        |> Repo.update()
    end
  end

  # A write is one transaction, so a refusal partway through a PATCH or a PUT
  # leaves nothing applied (RFC 7644 section 3.5.2), and an invitation, the
  # mail behind it, the membership and the audit rows commit together or not
  # at all. Locks are taken in one order: the connection, then any invitation
  # the write retires, then the organization seat row, then the user.
  # `Organizations.remove_member/3` and invitation acceptance take theirs in
  # the same order.
  #
  # Buying a seat is the one step that cannot run inside, because it is a
  # billing call. A write refused for seats under the expand policy expands
  # afterwards and runs once more from the start.
  #
  # Two things about nesting. A failed Multi anywhere inside rolls the write
  # back even when its caller answers `:ok`, so nothing in here may call one
  # that can fail on a condition it means to tolerate. And a unique violation
  # aborts the Postgres transaction, so nothing in here may catch one and
  # continue; the checks that would have been constraints are lookups under
  # the locks instead.
  defp write(connection, fun, retried? \\ false) do
    result =
      Repo.transaction(fn ->
        lock_connection!(connection)

        case fun.() do
          {:ok, value} -> value
          {:error, reason} -> Repo.rollback(reason)
        end
      end)

    case result do
      {:ok, value} ->
        {:ok, value}

      {:error, {:seats_exhausted, user}}
      when not retried? and connection.scim_seat_policy == "expand" ->
        SSO.expand_seat(connection, user, :scim)
        write(connection, fun, true)

      {:error, {:seats_exhausted, _user}} ->
        SSO.notify_seats_exhausted(connection, :scim)
        {:error, :seats_exhausted}

      {:error, :seat_limit_unknown} = error ->
        SSO.notify_seats_exhausted(connection, :scim)
        error

      {:error, reason} ->
        {:error, reason}
    end
  end

  # `FOR NO KEY UPDATE` serializes the provider's writes on this connection
  # without blocking the `FOR KEY SHARE` a login's identity insert takes on the
  # same row. Member removal takes `FOR UPDATE` here first as well.
  defp lock_connection!(connection) do
    Repo.one!(from(row in Connection, where: row.id == ^connection.id, lock: "FOR NO KEY UPDATE"))
  end

  # Derives the state and performs the two lazy repairs: an accepted
  # invitation hands its account over, and a userName newly verified by a
  # current member adopts the membership.
  defp resolve(resource, members \\ nil)

  defp resolve(%Resource{} = resource, members) do
    resource = resource |> Repo.preload([:user, :invitation]) |> repair()

    cond do
      resource.user_id && member?(resource.organization_id, resource.user_id, members) ->
        %{resource: resource, state: :member, user: resource.user}

      pending?(resource.invitation) ->
        %{resource: resource, state: :invited, user: nil}

      true ->
        %{resource: resource, state: :inactive, user: resource.user}
    end
  end

  defp repair(
         %Resource{user_id: nil, invitation: %OrganizationInvitation{} = invitation} = resource
       )
       when not is_nil(invitation.accepted_by_user_id) do
    adopt_user(resource, invitation.accepted_by_user_id)
  end

  defp repair(%Resource{user_id: nil} = resource) do
    with %User{} = user <-
           resolve_account(resource.connection_id, resource.organization_id, resource.user_name),
         true <- member?(resource.organization_id, user.id) do
      adopt_user(resource, user.id)
    else
      _no_match -> resource
    end
  end

  defp repair(resource), do: resource

  # Another handle already holding the account leaves this one alone. Every
  # path that binds an account to a handle, this one from a read, a write,
  # and an invitation acceptance, does so under the connection lock, so the
  # check cannot be overtaken and no unique violation can abort a write's
  # transaction. From a read this is its own short transaction; inside a
  # write it joins the one already holding the lock.
  defp adopt_user(resource, user_id) do
    {:ok, resource} =
      Repo.transaction(fn ->
        lock_connection!(%Connection{id: resource.connection_id})

        # Read again under the lock: a write that ran while this waited may
        # have bound or renamed the handle, and the match was made against
        # the name it had before.
        fresh = Repo.get!(Resource, resource.id) |> Repo.preload([:user, :invitation])

        cond do
          fresh.user_id || fresh.user_name != resource.user_name ->
            fresh

          holder?(fresh.connection_id, user_id) ->
            fresh

          true ->
            fresh
            |> change(user_id: user_id)
            |> Repo.update!()
            |> Repo.preload(:user, force: true)
        end
      end)

    resource
  end

  defp holder?(connection_id, user_id) do
    Repo.exists?(
      from(other in Resource,
        where: other.connection_id == ^connection_id,
        where: other.user_id == ^user_id
      )
    )
  end

  defp pending?(%OrganizationInvitation{} = invitation),
    do: OrganizationInvitation.pending?(invitation, DateTime.utc_now())

  defp pending?(_invitation), do: false

  # The handle is validated before the invitation goes out, so a create that
  # fails on its own attributes leaves no invitation behind.
  defp create_active(connection, user_name, external_id, audit_data) do
    attrs = %{user_name: user_name, external_id: external_id}

    case resolve_account(connection.id, connection.organization_id, user_name) do
      %User{} = user ->
        with {:ok, _handle} <- validate_resource(connection, attrs),
             {:ok, _membership} <- ensure_membership(connection, user, audit_data) do
          insert_resource(connection, Map.put(attrs, :user_id, user.id), audit_data)
        end

      nil ->
        with {:ok, _handle} <- validate_resource(connection, attrs),
             {:ok, invitation} <- obtain_invitation(connection, user_name, audit_data) do
          insert_resource(connection, Map.put(attrs, :invitation_id, invitation.id), audit_data)
        end
    end
  end

  # Reactivation of an existing handle: the same matching as a create, applied
  # to the row the provider already holds.
  defp activate(_connection, %{state: state} = resolved, _audit_data)
       when state in [:member, :invited] do
    {:ok, resolved}
  end

  defp activate(connection, %{resource: resource}, audit_data) do
    case resolve_account(connection.id, connection.organization_id, resource.user_name) do
      %User{} = user ->
        with {:ok, _membership} <- ensure_membership(connection, user, audit_data),
             {:ok, resource} <- update_resource(resource, %{user_id: user.id}) do
          {:ok, resolve(resource)}
        end

      nil ->
        with {:ok, invitation} <- obtain_invitation(connection, resource.user_name, audit_data),
             {:ok, resource} <-
               update_resource(resource, %{invitation_id: invitation.id, user_id: nil}) do
          {:ok, resolve(resource)}
        end
    end
  end

  # The seat is claimed and the membership inserted in the write's transaction.
  # A membership that already exists (JIT, an administrator) is adopted rather
  # than refused: the person the provider asked for is a member. It costs no
  # seat and needs no admission, so a full organization, or one whose 2FA
  # policy the person does not yet satisfy, still provisions someone who is
  # already in it.
  #
  # The seat lock comes before the role is read, and every other path that
  # inserts a membership takes the same lock first, so the role read is exact
  # and the insert cannot hit the unique index.
  defp ensure_membership(connection, user, audit_data) do
    organization = connection.organization

    if User.organization?(user) do
      {:error, :invalid_value}
    else
      organization = Seats.lock!(organization)

      if Organizations.get_role(organization, user) do
        {:ok, :already_member}
      else
        with :ok <- OrganizationTFA.admit(organization, user),
             {:ok, _usage} <- claim_seat(organization, user) do
          insert_membership(connection, organization, user, audit_data)
        end
      end
    end
  end

  # The refusal carries the person, so the retry outside the transaction can
  # buy the seat for exactly them.
  defp claim_seat(organization, user) do
    case Seats.claim(organization, unknown: :deny) do
      {:error, :seats_exhausted} -> {:error, {:seats_exhausted, user}}
      other -> other
    end
  end

  # Joining an organization is something the person finds out about, whether
  # an administrator added them or their identity provider did. The mail is
  # queued with the membership, so a delivery problem never answers the
  # provider after the membership has committed.
  defp insert_membership(connection, organization, user, audit_data) do
    organization_user = %OrganizationUser{
      organization_id: organization.id,
      user_id: user.id
    }

    with {:ok, _member} <-
           Repo.insert(
             Organization.add_member(organization_user, %{"role" => connection.scim_role})
           ) do
      insert_audit!(audit_data, "organization.member.add", {organization, user})
      Organizations.send_member_added_email(organization, Repo.preload(user, :emails))
      {:ok, :joined}
    end
  end

  defp obtain_invitation(connection, user_name, audit_data) do
    organization = connection.organization

    case OrganizationInvitations.get_pending_by_email(organization, user_name) do
      %OrganizationInvitation{} = invitation ->
        {:ok, invitation}

      nil ->
        case OrganizationInvitations.invite(
               organization,
               %{"email" => user_name, "role" => connection.scim_role},
               nil,
               audit: audit_data
             ) do
          {:ok, invitation} ->
            {:ok, invitation}

          # `invite/4` matched a member through a username or an unverified
          # address. A verified email never reached this branch, so binding
          # the account here would trust exactly what the design refuses to.
          {:error, :already_member} ->
            {:error, :unverified_member}

          {:error, %Ecto.Changeset{} = changeset} ->
            {:error, changeset}
        end
    end
  end

  defp apply_changes(connection, resolved, changes, audit_data) do
    with {:ok, resolved} <- apply_attributes(connection, resolved, changes, audit_data) do
      case Map.fetch(changes, :active) do
        {:ok, true} -> activate(connection, resolved, audit_data)
        {:ok, false} -> deactivate(connection, resolved, audit_data)
        :error -> {:ok, resolved}
      end
    end
  end

  defp apply_attributes(connection, resolved, changes, audit_data) do
    with {:ok, resolved} <- apply_user_name(connection, resolved, changes, audit_data) do
      case Map.fetch(changes, :external_id) do
        {:ok, external_id} ->
          with {:ok, resource} <- update_resource(resolved.resource, %{external_id: external_id}) do
            audit!(audit_data, "sso.scim.resource.update", connection, resource)
            {:ok, %{resolved | resource: resource}}
          end

        :error ->
          {:ok, resolved}
      end
    end
  end

  defp apply_user_name(connection, resolved, %{user_name: user_name}, audit_data) do
    user_name = Resource.normalize_user_name(user_name)

    cond do
      user_name == resolved.resource.user_name ->
        {:ok, resolved}

      not Resource.email_shaped?(user_name) ->
        {:error, :invalid_value}

      # While a membership stands the name is a label; deactivate and
      # reactivate is the account-transfer path.
      resolved.state == :member ->
        with {:ok, resource} <- update_resource(resolved.resource, %{user_name: user_name}) do
          audit!(audit_data, "sso.scim.resource.update", connection, resource)
          {:ok, %{resolved | resource: resource}}
        end

      # An inactive handle may still point at the account it used to name and
      # at the invitation that once named it, which a hand removal leaves
      # behind. Renamed, it means the new address and nothing else: a
      # following activation or deactivation acts on whoever that address
      # matches, and neither stale pointer can outlive the rename.
      resolved.state == :inactive ->
        with {:ok, resource} <-
               update_resource(resolved.resource, %{
                 user_name: user_name,
                 user_id: nil,
                 invitation_id: nil
               }) do
          audit!(audit_data, "sso.scim.resource.update", connection, resource)
          {:ok, %{resolved | resource: resource, user: nil}}
        end

      # An invited person renamed is an invitation to the new address. The old
      # invitation is locked first, so an acceptance of it either lands before
      # the rename and is undone the way a deactivation undoes one, or waits
      # and finds the invitation revoked.
      resolved.state == :invited ->
        old_invitation = lock_invitation(resolved.resource.invitation_id)

        with {:ok, invitation} <- obtain_invitation(connection, user_name, audit_data),
             {:ok, resource} <-
               update_resource(resolved.resource, %{
                 user_name: user_name,
                 invitation_id: invitation.id
               }),
             :ok <- retire_locked(connection, old_invitation, audit_data) do
          audit!(audit_data, "sso.scim.resource.update", connection, resource)
          {:ok, resolve(resource)}
        end
    end
  end

  defp apply_user_name(_connection, resolved, _changes, _audit_data), do: {:ok, resolved}

  # What a deactivation leaves behind: no membership, no live invitation that
  # could re-admit the address, no membership created by an acceptance that
  # raced it, and no pointer on the handle. That holds whichever state the
  # handle was in: an invitation sent by hand for the address names the person
  # the provider just deprovisioned, and following it would put them straight
  # back in, so it is retired even when the handle itself was already inactive.
  #
  # The invitations are locked before the membership is removed, the order
  # acceptance uses (invitation, then organization), and the last-member and
  # last-admin guards refuse the whole deactivation, never half of it.
  #
  # A deactivation is done when the handle reads inactive. It is resolved
  # again here rather than trusting the state the request began with, because
  # an earlier operation may have renamed it onto an address a current member
  # holds; and it is resolved once more after each removal, because with the
  # bound account gone the address can still name a member, added by hand or
  # matched through their identity, who is the person the provider means.
  #
  # This ends because every round that does not finish removes a membership:
  # with both pointers cleared, the only way the handle resolves to anything is
  # by matching a current member through the address, and the next round
  # removes that member. Identities do not make the address unique, so several
  # members can share one, and each takes a round.
  defp deactivate(connection, resolved, audit_data) do
    deactivate_round(connection, resolve(resolved.resource), audit_data)
  end

  defp deactivate_round(connection, resolved, audit_data) do
    resource = resolved.resource
    own = lock_invitation(resource.invitation_id)
    matching = lock_matching_invitation(connection, resource, own)

    with :ok <- remove_deactivated(connection, resolved, audit_data),
         :ok <- retire_locked(connection, own, audit_data),
         :ok <- retire_locked(connection, matching, audit_data),
         {:ok, resource} <- update_resource(resource, %{invitation_id: nil, user_id: nil}) do
      case resolve(resource) do
        %{state: :inactive} = resolved -> {:ok, resolved}
        resolved -> deactivate_round(connection, resolved, audit_data)
      end
    end
  end

  defp remove_deactivated(connection, %{state: :member, user: user}, audit_data) do
    remove_if_member(connection, user, audit_data)
  end

  defp remove_deactivated(_connection, _resolved, _audit_data), do: :ok

  # The role is checked first because `remove_member/3` answers `:ok` for a
  # non-member by failing its Multi, and a failed Multi inside the write's
  # transaction rolls the whole write back whatever the caller makes of it.
  defp remove_if_member(connection, user, audit_data) do
    organization = connection.organization

    if Organizations.get_role(organization, user) do
      Organizations.remove_member(organization, user, audit: audit_data)
    else
      :ok
    end
  end

  defp lock_invitation(nil), do: nil

  defp lock_invitation(invitation_id) do
    Repo.one(
      from(invitation in OrganizationInvitation,
        where: invitation.id == ^invitation_id,
        lock: "FOR UPDATE"
      )
    )
  end

  defp lock_matching_invitation(connection, resource, own) do
    case OrganizationInvitations.get_pending_by_email(connection.organization, resource.user_name) do
      %OrganizationInvitation{id: id} when is_nil(own) or id != own.id -> lock_invitation(id)
      _own_or_none -> nil
    end
  end

  # Revokes a locked invitation, or undoes the acceptance that won the race to
  # it: the membership it produced is removed the way a deactivation removes
  # one, and the guards' refusals come back rather than being dropped.
  defp retire_locked(_connection, nil, _audit_data), do: :ok

  defp retire_locked(connection, %OrganizationInvitation{} = locked, audit_data) do
    cond do
      locked.accepted_at ->
        remove_acceptor(connection, locked.accepted_by_user_id, audit_data)

      is_nil(locked.revoked_at) ->
        with {:ok, _invitation} <-
               OrganizationInvitations.revoke(connection.organization, locked, audit: audit_data) do
          :ok
        end

      true ->
        :ok
    end
  end

  defp remove_acceptor(connection, user_id, audit_data) do
    case user_id && Repo.get(User, user_id) do
      %User{} = acceptor -> remove_if_member(connection, acceptor, audit_data)
      nil -> :ok
    end
  end

  # Handles that can be bound to an account are repaired before the members
  # without one are looked for, so an accepted invitation's handle claims its
  # account rather than an import materializing a second row for the same
  # person. Membership is compared by account, not by count: a handle whose
  # account was removed by hand still carries the account.
  defp materialize_members(connection, audit_data) do
    from(resource in resources_query(connection), where: is_nil(resource.user_id))
    |> Repo.all()
    |> Repo.preload([:user, :invitation])
    |> Enum.each(&repair/1)

    represented =
      from(resource in resources_query(connection),
        where: not is_nil(resource.user_id),
        select: resource.user_id
      )
      |> Repo.all()
      |> MapSet.new()

    provider_emails =
      from(identity in Identity,
        where: identity.connection_id == ^connection.id,
        select: {identity.user_id, identity.provider_email}
      )
      |> Repo.all()
      |> Map.new()

    for organization_user <- Organizations.all_members(connection.organization, user: :emails),
        organization_user.user_id not in represented do
      user = organization_user.user
      user_name = provider_emails[user.id] || primary_email(user)

      if user_name do
        materialize_member(connection, user, user_name, audit_data)
      end
    end

    :ok
  end

  # An account holds at most one handle per connection, so a member the
  # provider asks for under a new address is relabeled rather than given a
  # second row. Without that the insert conflicts on the account, the filter
  # answers nothing, and the provider's recovery path never converges.
  # Under the connection lock like every other write to a handle, so the
  # lookups below are exact and neither the relabel nor the insert can hit a
  # unique index. Two members presenting the same address keep the row that
  # exists; the filter asked for the address, and that row answers it.
  defp materialize_member(connection, user, user_name, audit_data) do
    # The identity's provider email arrives as the provider sent it; the row
    # stores it normalized, and so must every comparison against the rows.
    user_name = Resource.normalize_user_name(user_name)

    {:ok, resolved} =
      Repo.transaction(fn ->
        lock_connection!(connection)

        case Repo.get_by(Resource, connection_id: connection.id, user_id: user.id) do
          %Resource{user_name: ^user_name} = resource ->
            resolve(resource)

          %Resource{} = resource ->
            case get_resource_by_user_name(connection, user_name) do
              %Resource{} = taken ->
                resolve(taken)

              nil ->
                {:ok, resource} = update_resource(resource, %{user_name: user_name})
                audit!(audit_data, "sso.scim.resource.update", connection, resource)
                resolve(resource)
            end

          nil ->
            case get_resource_by_user_name(connection, user_name) do
              %Resource{} = taken ->
                resolve(taken)

              nil ->
                connection
                |> Resource.build()
                |> Resource.changeset(%{user_name: user_name, user_id: user.id})
                |> Repo.insert!()
                |> resolve()
            end
        end
      end)

    resolved
  end

  # Verified as well as primary: presenting an unverified address as the
  # match key would let the handle bind to whoever typed the address first
  # rather than whoever owns it.
  defp primary_email(user) do
    Enum.find_value(user.emails, fn email -> email.verified && email.primary && email.email end)
  end

  defp insert_resource(connection, attrs, audit_data) do
    connection
    |> Resource.build()
    |> Resource.changeset(attrs)
    |> Repo.insert()
    |> normalize_write_error()
    |> case do
      {:ok, resource} ->
        audit!(audit_data, "sso.scim.resource.create", connection, resource)
        {:ok, resolve(resource)}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp validate_resource(connection, attrs) do
    changeset = connection |> Resource.build() |> Resource.changeset(attrs)
    if changeset.valid?, do: {:ok, changeset}, else: {:error, changeset}
  end

  defp update_resource(resource, attrs) do
    resource
    |> Resource.changeset(attrs)
    |> Repo.update()
    |> normalize_write_error()
  end

  defp normalize_write_error({:ok, resource}), do: {:ok, resource}

  defp normalize_write_error({:error, %Ecto.Changeset{} = changeset}) do
    if unique_violation?(changeset), do: {:error, :uniqueness}, else: {:error, changeset}
  end

  defp unique_violation?(%Ecto.Changeset{errors: errors}) do
    Enum.any?(errors, fn {_field, {_message, opts}} -> opts[:constraint] == :unique end)
  end

  defp resources_query(connection) do
    from(resource in Resource, where: resource.connection_id == ^connection.id)
  end

  defp get_resource_by_user_name(connection, user_name) do
    Repo.get_by(Resource, connection_id: connection.id, user_name: user_name)
  end

  # The provider's userName names an account two ways: the address the person
  # authenticated with through this connection, and any verified email on a
  # Hex account. The first is what reaches a member whose Hex account holds no
  # verified copy of the work address, which is the common case for someone who
  # signed up before the organization did and never added it.
  defp resolve_account(connection_id, organization_id, user_name) do
    member_by_provider_email(connection_id, organization_id, user_name) ||
      verified_email_owner(user_name)
  end

  defp member_by_provider_email(connection_id, organization_id, user_name) do
    Repo.one(
      from(identity in Identity,
        join: user in assoc(identity, :user),
        join: organization_user in OrganizationUser,
        on:
          organization_user.user_id == identity.user_id and
            organization_user.organization_id == ^organization_id,
        where: identity.connection_id == ^connection_id,
        where: fragment("lower(?)", identity.provider_email) == ^user_name,
        select: user,
        limit: 1
      )
    )
  end

  defp verified_email_owner(user_name) do
    case Users.get_email(user_name, [:user]) do
      %{user: %User{} = user} -> unless User.organization?(user), do: user
      _missing -> nil
    end
  end

  defp member?(_organization_id, user_id, %MapSet{} = members), do: user_id in members

  defp member?(organization_id, user_id, nil), do: member?(organization_id, user_id)

  defp member?(organization_id, user_id) do
    Repo.exists?(
      from(organization_user in OrganizationUser,
        where: organization_user.organization_id == ^organization_id,
        where: organization_user.user_id == ^user_id
      )
    )
  end

  # Every write the provider makes leaves a row, including the ones that change
  # only the handle: a relabel decides which account a later reactivation
  # binds, so it has to be readable afterwards.
  defp audit!(audit_data, action, connection, resource) do
    insert_audit!(audit_data, action, {
      connection.organization,
      %{
        scim_id: resource.scim_id,
        user_name: resource.user_name,
        external_id: resource.external_id
      }
    })
  end

  defp insert_audit!(audit_data, action, params) do
    audit_data
    |> AuditLog.build(action, params)
    |> Repo.insert!()
  end

  defp validate_user_name(user_name) when is_binary(user_name) do
    user_name = Resource.normalize_user_name(user_name)

    if Resource.email_shaped?(user_name) do
      {:ok, user_name}
    else
      {:error, :invalid_value}
    end
  end

  defp validate_user_name(_user_name), do: {:error, :invalid_value}

  defp optional_string(value) when is_binary(value) and value != "", do: value
  defp optional_string(_value), do: nil

  # Entra sends the string form. Anything else is refused rather than read as
  # active: `active` decides whether someone is in the organization, and a
  # value we do not understand is not consent to put them there.
  defp active_value(nil), do: {:ok, :unchanged}
  defp active_value(true), do: {:ok, true}
  defp active_value(false), do: {:ok, false}

  defp active_value(value) when is_binary(value) do
    case String.downcase(value) do
      "true" -> {:ok, true}
      "false" -> {:ok, false}
      _other -> {:error, :invalid_value}
    end
  end

  defp active_value(_value), do: {:error, :invalid_value}

  defp patch_changes(operations) do
    Enum.reduce_while(operations, {:ok, []}, fn operation, {:ok, changes} ->
      case patch_change(operation) do
        {:ok, change} -> {:cont, {:ok, [change | changes]}}
        :ignore -> {:cont, {:ok, changes}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
    |> case do
      {:ok, changes} -> {:ok, Enum.reverse(changes)}
      error -> error
    end
  end

  defp patch_change(%{"op" => op} = operation) when is_binary(op) do
    value = Map.get(operation, "value")

    with {:ok, path} <- normalize_path(Map.get(operation, "path")) do
      case {String.downcase(op), path} do
        {op, nil} when op in ["replace", "add"] and is_map(value) ->
          value_object_changes(value)

        # A patch that names `active` has to say which way; PUT is where an
        # absent value means unchanged.
        {op, "active"} when op in ["replace", "add"] ->
          case active_value(value) do
            {:ok, :unchanged} -> {:error, :invalid_value}
            {:ok, active} -> {:ok, %{active: active}}
            {:error, reason} -> {:error, reason}
          end

        {op, "username"} when op in ["replace", "add"] and is_binary(value) ->
          {:ok, %{user_name: value}}

        {op, "externalid"} when op in ["replace", "add"] ->
          {:ok, %{external_id: optional_string(value)}}

        {"remove", "externalid"} ->
          {:ok, %{external_id: nil}}

        {"remove", path} when path in ["active", "username"] ->
          {:error, :invalid_path}

        # Attributes we do not store; the echo never includes them, so there is
        # nothing for the operation to change.
        {op, _ignored} when op in ["replace", "add", "remove"] ->
          :ignore

        _unknown ->
          {:error, :invalid_path}
      end
    end
  end

  defp patch_change(_operation), do: {:error, :invalid_path}

  defp normalize_path(nil), do: {:ok, nil}

  defp normalize_path(path) when is_binary(path) do
    path = String.downcase(path)
    {:ok, String.replace_prefix(path, @user_urn_prefix, "")}
  end

  defp normalize_path(_path), do: {:error, :invalid_path}

  # RFC 7643 makes attribute names case-insensitive, and the providers do use
  # different casings for the same attribute.
  defp value_object_changes(value) do
    Enum.reduce_while(value, {:ok, %{}}, fn {key, value}, {:ok, changes} ->
      case {String.downcase(to_string(key)), value} do
        {"active", value} ->
          case active_value(value) do
            {:ok, :unchanged} -> {:halt, {:error, :invalid_value}}
            {:ok, active} -> {:cont, {:ok, Map.put(changes, :active, active)}}
            {:error, reason} -> {:halt, {:error, reason}}
          end

        {"username", user_name} when is_binary(user_name) ->
          {:cont, {:ok, Map.put(changes, :user_name, user_name)}}

        {"externalid", external_id} ->
          {:cont, {:ok, Map.put(changes, :external_id, optional_string(external_id))}}

        {_other, _value} ->
          {:cont, {:ok, changes}}
      end
    end)
  end
end
