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

  # Entra maps `externalId` from `mailNickname` by default, which repeats after
  # a rehire, so two rows under one id is a shape the provider produces without
  # malice. The oldest wins rather than the request failing.
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
    end
  end

  @doc """
  Full replace of the attributes we own: `userName`, `externalId`, and the
  `active` transition. Everything else in the payload is ignored.
  """
  def replace_user(%Connection{} = connection, scim_id, params, audit: audit_data) do
    with {:ok, resolved} <- get_user(connection, scim_id),
         {:ok, user_name} <- validate_user_name(params["userName"]),
         {:ok, active} <- active_value(params["active"]) do
      changes = %{
        user_name: user_name,
        external_id: optional_string(params["externalId"])
      }

      changes = if active == :unchanged, do: changes, else: Map.put(changes, :active, active)

      apply_changes(connection, resolved, changes, audit_data)
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
    with {:ok, resolved} <- get_user(connection, scim_id) do
      # Operations run one at a time, in array order, as RFC 7644 requires:
      # `active` then `userName` means activate the account this name matches
      # now and relabel afterwards, which is not the same as activating under
      # the final name.
      Enum.reduce_while(operations, {:ok, resolved}, fn operation, {:ok, resolved} ->
        case patch_change(operation) do
          {:ok, change} ->
            case apply_changes(connection, resolved, change, audit_data) do
              {:ok, resolved} -> {:cont, {:ok, resolved}}
              {:error, reason} -> {:halt, {:error, reason}}
            end

          :ignore ->
            {:cont, {:ok, resolved}}

          {:error, reason} ->
            {:halt, {:error, reason}}
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
    with {:ok, resolved} <- get_user(connection, scim_id),
         {:ok, resolved} <- deactivate(connection, resolved, audit_data) do
      Repo.delete!(resolved.resource)
      audit!(audit_data, "sso.scim.resource.delete", connection, resolved.resource)
      :ok
    end
  end

  # -- state resolution ------------------------------------------------------

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

  defp adopt_user(resource, user_id) do
    resource
    |> change(user_id: user_id)
    |> unique_constraint([:connection_id, :user_id])
    |> Repo.update()
    |> case do
      {:ok, resource} -> Repo.preload(resource, :user, force: true)
      # Another resource already holds this account; leave this one alone.
      {:error, _changeset} -> resource
    end
  end

  defp pending?(%OrganizationInvitation{} = invitation),
    do: OrganizationInvitation.pending?(invitation, DateTime.utc_now())

  defp pending?(_invitation), do: false

  # -- create and activation -------------------------------------------------

  defp create_active(connection, user_name, external_id, audit_data) do
    case resolve_account(connection.id, connection.organization_id, user_name) do
      %User{} = user ->
        create_member(connection, user_name, external_id, user, audit_data, _retried? = false)

      nil ->
        with {:ok, invitation, _provenance} <-
               obtain_invitation(connection, user_name, audit_data) do
          insert_resource(
            connection,
            %{
              user_name: user_name,
              external_id: external_id,
              invitation_id: invitation.id
            },
            audit_data
          )
        end
    end
  end

  defp create_member(connection, user_name, external_id, user, audit_data, retried?) do
    attrs = %{user_name: user_name, external_id: external_id, user_id: user.id}

    result =
      Repo.transaction(fn ->
        with {:ok, membership} <- ensure_membership(connection, user, audit_data) do
          case do_insert_resource(connection, attrs) do
            {:ok, resource} -> {resource, membership}
            {:error, reason} -> Repo.rollback(reason)
          end
        else
          {:error, reason} -> Repo.rollback(reason)
        end
      end)

    case result do
      {:ok, {resource, membership}} ->
        if membership == :joined, do: notify_member(connection, user)
        audit!(audit_data, "sso.scim.resource.create", connection, resource)
        {:ok, resolve(resource)}

      {:error, :seats_exhausted} when not retried? ->
        retry_after_expansion(connection, user, fn ->
          create_member(connection, user_name, external_id, user, audit_data, true)
        end)

      {:error, reason} ->
        notify_seats(connection, reason)
        {:error, reason}
    end
  end

  # Reactivation of an existing handle: the same matching as a create, applied
  # to the row the provider already holds.
  defp activate(_connection, %{state: state} = resolved, _audit_data)
       when state in [:member, :invited] do
    {:ok, resolved}
  end

  defp activate(connection, %{resource: resource}, audit_data) do
    activate_resource(connection, resource, audit_data, _retried? = false)
  end

  defp activate_resource(connection, resource, audit_data, retried?) do
    case resolve_account(connection.id, connection.organization_id, resource.user_name) do
      %User{} = user ->
        result =
          Repo.transaction(fn ->
            with {:ok, membership} <- ensure_membership(connection, user, audit_data) do
              case update_resource(resource, %{user_id: user.id}) do
                {:ok, resource} -> {resource, membership}
                {:error, reason} -> Repo.rollback(reason)
              end
            else
              {:error, reason} -> Repo.rollback(reason)
            end
          end)

        case result do
          {:ok, {resource, membership}} ->
            if membership == :joined, do: notify_member(connection, user)
            {:ok, resolve(resource)}

          {:error, :seats_exhausted} when not retried? ->
            retry_after_expansion(connection, user, fn ->
              activate_resource(connection, resource, audit_data, true)
            end)

          {:error, reason} ->
            notify_seats(connection, reason)
            {:error, reason}
        end

      nil ->
        with {:ok, invitation, _provenance} <-
               obtain_invitation(connection, resource.user_name, audit_data),
             {:ok, resource} <-
               update_resource(resource, %{invitation_id: invitation.id, user_id: nil}) do
          {:ok, resolve(resource)}
        end
    end
  end

  # The seat is claimed and the membership inserted in the caller's
  # transaction. A concurrent membership (JIT, an administrator) is adopted
  # rather than refused: the person the provider asked for is a member.
  #
  # The seat lock comes before the role is read, so the membership set cannot
  # change between the two and a concurrent insert cannot abort the caller's
  # transaction on the unique index.
  defp ensure_membership(connection, user, audit_data) do
    organization = connection.organization

    if User.organization?(user) do
      {:error, :invalid_value}
    else
      claim_membership(connection, organization, user, audit_data)
    end
  end

  # Already a member costs no seat and needs no admission, so a full
  # organization, or one whose 2FA policy the person does not yet satisfy,
  # still provisions someone who is already in it.
  defp claim_membership(connection, organization, user, audit_data) do
    organization = Seats.lock!(organization)

    if Organizations.get_role(organization, user) do
      {:ok, :already_member}
    else
      with :ok <- OrganizationTFA.admit(organization, user),
           {:ok, _usage} <- Seats.claim(organization, unknown: :deny) do
        insert_membership(connection, organization, user, audit_data)
      end
    end
  end

  defp insert_membership(connection, organization, user, audit_data) do
    organization_user = %OrganizationUser{
      organization_id: organization.id,
      user_id: user.id
    }

    case Repo.insert(
           Organization.add_member(organization_user, %{"role" => connection.scim_role})
         ) do
      {:ok, _member} ->
        insert_audit!(audit_data, "organization.member.add", {organization, user})
        {:ok, :joined}

      {:error, %Ecto.Changeset{} = changeset} ->
        if unique_violation?(changeset), do: {:ok, :already_member}, else: {:error, changeset}
    end
  end

  # Joining an organization is something the person finds out about, whether an
  # administrator added them or their identity provider did.
  defp notify_member(connection, user) do
    Organizations.send_member_added_email(
      connection.organization,
      Repo.preload(user, :emails)
    )
  end

  defp notify_seats(connection, reason)
       when reason in [:seats_exhausted, :seat_limit_unknown] do
    SSO.notify_seats_exhausted(connection, :scim)
  end

  defp notify_seats(_connection, _reason), do: :ok

  defp retry_after_expansion(connection, user, retry) do
    if connection.scim_seat_policy == "expand" do
      SSO.expand_seat(connection, user, :scim)
      retry.()
    else
      {:error, :seats_exhausted}
    end
  end

  defp obtain_invitation(connection, user_name, audit_data) do
    organization = connection.organization

    case OrganizationInvitations.get_pending_by_email(organization, user_name) do
      %OrganizationInvitation{} = invitation ->
        {:ok, invitation, :adopted}

      nil ->
        case OrganizationInvitations.invite(
               organization,
               %{"email" => user_name, "role" => connection.scim_role},
               nil,
               audit: audit_data
             ) do
          {:ok, invitation} ->
            {:ok, invitation, :created}

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

  # -- attribute changes and deactivation ------------------------------------

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
      resolved.state in [:member, :inactive] ->
        with {:ok, resource} <- update_resource(resolved.resource, %{user_name: user_name}) do
          audit!(audit_data, "sso.scim.resource.update", connection, resource)
          {:ok, %{resolved | resource: resource}}
        end

      # An invited person renamed is an invitation to the new address. The
      # row is updated before the old invitation is retired, so a rename that
      # fails on a taken name leaves the original untouched; only an
      # invitation this rename itself created is taken back on failure.
      resolved.state == :invited ->
        old_invitation_id = resolved.resource.invitation_id

        with {:ok, invitation, provenance} <-
               obtain_invitation(connection, user_name, audit_data) do
          case update_resource(resolved.resource, %{
                 user_name: user_name,
                 invitation_id: invitation.id
               }) do
            {:ok, resource} ->
              audit!(audit_data, "sso.scim.resource.update", connection, resource)
              retire_accepted_or_revoke(connection, old_invitation_id, audit_data)
              {:ok, resolve(resource)}

            {:error, reason} ->
              if provenance == :created do
                retire_invitation(connection, invitation.id, audit_data)
              end

              {:error, reason}
          end
        end
    end
  end

  defp apply_user_name(_connection, resolved, _changes, _audit_data), do: {:ok, resolved}

  # A rename whose old invitation was accepted while it was in flight leaves a
  # membership the handle no longer points at, so the acceptance is undone the
  # way a deactivation undoes one.
  defp retire_accepted_or_revoke(connection, invitation_id, audit_data) do
    case retire_invitation(connection, invitation_id, audit_data) do
      {:accepted, user_id} -> remove_acceptor(connection, user_id, audit_data)
      _retired -> :ok
    end
  end

  # One transaction over the membership and the invitation: the last-member
  # guard can refuse either removal, and a deactivation that leaves the
  # invitation revoked but the membership standing is worse than one that does
  # nothing.
  defp deactivate(connection, %{state: :member} = resolved, audit_data) do
    organization = connection.organization

    Repo.transaction(fn ->
      with :ok <- Organizations.remove_member(organization, resolved.user, audit: audit_data),
           {:ok, cleared} <- retire_and_clear(connection, resolved.resource, audit_data) do
        cleared
      else
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end

  defp deactivate(connection, %{state: :invited} = resolved, audit_data) do
    retire_and_clear(connection, resolved.resource, audit_data)
  end

  defp deactivate(_connection, %{state: :inactive} = resolved, _audit_data), do: {:ok, resolved}

  # What a deactivation leaves behind: no live invitation that could re-admit
  # the address, no membership created by an acceptance that raced it, and no
  # dangling pointer on the handle.
  #
  # An invitation sent by hand for the same address is retired too. It names
  # the person the provider just deprovisioned, and following it would put them
  # straight back in.
  defp retire_and_clear(connection, resource, audit_data) do
    retire_matching_invitation(connection, resource, audit_data)

    case retire_invitation(connection, resource.invitation_id, audit_data) do
      {:accepted, user_id} ->
        case remove_acceptor(connection, user_id, audit_data) do
          {:error, reason} -> {:error, reason}
          :ok -> clear_invitation(resource)
        end

      _retired ->
        clear_invitation(resource)
    end
  end

  defp retire_matching_invitation(connection, resource, audit_data) do
    case OrganizationInvitations.get_pending_by_email(
           connection.organization,
           resource.user_name
         ) do
      %OrganizationInvitation{id: id} when id != resource.invitation_id ->
        retire_invitation(connection, id, audit_data)

      _own_or_none ->
        :ok
    end
  end

  defp remove_acceptor(connection, user_id, audit_data) do
    organization = connection.organization
    acceptor = user_id && Repo.get(User, user_id)

    if acceptor && Organizations.get_role(organization, acceptor) do
      Organizations.remove_member(organization, acceptor, audit: audit_data)
    else
      :ok
    end
  end

  defp clear_invitation(resource) do
    with {:ok, resource} <- update_resource(resource, %{invitation_id: nil, user_id: nil}) do
      {:ok, resolve(resource)}
    end
  end

  # Revokes under a row lock, or reports that an acceptance won the race, so
  # revocation never stamps an accepted row while its membership walks away.
  defp retire_invitation(_connection, nil, _audit_data), do: :none

  defp retire_invitation(connection, invitation_id, audit_data) do
    {:ok, outcome} =
      Repo.transaction(fn ->
        locked =
          Repo.one(
            from(invitation in OrganizationInvitation,
              where: invitation.id == ^invitation_id,
              lock: "FOR UPDATE"
            )
          )

        cond do
          is_nil(locked) ->
            :none

          locked.accepted_at ->
            {:accepted, locked.accepted_by_user_id}

          is_nil(locked.revoked_at) ->
            {:ok, _invitation} =
              OrganizationInvitations.revoke(connection.organization, locked, audit: audit_data)

            :revoked

          true ->
            :none
        end
      end)

    outcome
  end

  # -- materialization -------------------------------------------------------

  defp materialize_members(connection, audit_data) do
    represented =
      from(resource in resources_query(connection),
        where: not is_nil(resource.user_id),
        select: resource.user_id
      )
      |> Repo.all()
      |> MapSet.new()

    if Seats.used(connection.organization) > MapSet.size(represented) do
      materialize_missing(connection, represented, audit_data)
    end

    :ok
  end

  defp materialize_missing(connection, represented, audit_data) do
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
  end

  # An account holds at most one handle per connection, so a member the
  # provider asks for under a new address is relabeled rather than given a
  # second row. Without that the insert conflicts on the account, the filter
  # answers nothing, and the provider's recovery path never converges.
  defp materialize_member(connection, user, user_name, audit_data) do
    case Repo.get_by(Resource, connection_id: connection.id, user_id: user.id) do
      %Resource{user_name: ^user_name} = resource ->
        resolve(resource)

      %Resource{} = resource ->
        case update_resource(resource, %{user_name: user_name}) do
          {:ok, resource} ->
            audit!(audit_data, "sso.scim.resource.update", connection, resource)
            resolve(resource)

          {:error, _taken} ->
            refetch(connection, user_name)
        end

      nil ->
        insert_materialized(connection, user, user_name)
    end
  end

  # Best-effort under races and collisions: `on_conflict: :nothing` covers a
  # concurrent import or two members presenting the same address, and the read
  # path re-resolves whatever row won.
  defp insert_materialized(connection, user, user_name) do
    connection
    |> Resource.build()
    |> Resource.changeset(%{user_name: user_name, user_id: user.id})
    |> Repo.insert(on_conflict: :nothing)
    |> case do
      {:ok, %Resource{id: nil}} -> refetch(connection, user_name)
      {:ok, resource} -> resolve(resource)
      {:error, _changeset} -> refetch(connection, user_name)
    end
  end

  defp refetch(connection, user_name) do
    case get_resource_by_user_name(connection, user_name) do
      %Resource{} = resource -> resolve(resource)
      nil -> nil
    end
  end

  # Verified as well as primary: presenting an unverified address as the
  # match key would let the handle bind to whoever typed the address first
  # rather than whoever owns it.
  defp primary_email(user) do
    Enum.find_value(user.emails, fn email -> email.verified && email.primary && email.email end)
  end

  # -- persistence helpers ---------------------------------------------------

  defp insert_resource(connection, attrs, audit_data) do
    with {:ok, resource} <- do_insert_resource(connection, attrs) do
      audit!(audit_data, "sso.scim.resource.create", connection, resource)
      {:ok, resolve(resource)}
    end
  end

  defp do_insert_resource(connection, attrs) do
    connection
    |> Resource.build()
    |> Resource.changeset(attrs)
    |> Repo.insert()
    |> normalize_write_error()
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

  # -- SCIM value parsing ----------------------------------------------------

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

  defp patch_change(%{"op" => op} = operation) when is_binary(op) do
    value = Map.get(operation, "value")

    with {:ok, path} <- normalize_path(Map.get(operation, "path")) do
      case {String.downcase(op), path} do
        {op, nil} when op in ["replace", "add"] and is_map(value) ->
          value_object_changes(value)

        {op, "active"} when op in ["replace", "add"] ->
          with {:ok, active} <- active_value(value), do: {:ok, %{active: active}}

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
