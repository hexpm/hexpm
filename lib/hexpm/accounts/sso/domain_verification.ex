defmodule Hexpm.Accounts.SSO.DomainVerification do
  use Hexpm.Context

  alias Hexpm.Accounts.SSO, as: SSOContext
  alias Hexpm.Accounts.{Organization, OrganizationUser, SSO.Features}
  alias Hexpm.Accounts.SSO.{Connection, Domain, DomainName, DomainResolver}

  @lease_seconds 7 * 24 * 60 * 60
  @revalidation_interval_seconds 24 * 60 * 60
  @default_revalidation_limit 100
  @default_expiration_limit 100
  @max_domains_per_organization 10

  @doc false
  def max_revalidation_batch_size, do: @default_revalidation_limit

  def list(organization) do
    if Features.enabled?(organization) do
      expire_leases(organization_id: organization.id)

      from(domain in Domain,
        where: domain.organization_id == ^organization.id,
        order_by: [asc: domain.domain]
      )
      |> Repo.all()
    else
      []
    end
  end

  def get(organization, id) do
    if Features.enabled?(organization) do
      expire_leases(organization_id: organization.id)

      Repo.get_by(Domain, id: id, organization_id: organization.id)
      |> Repo.preload(:organization)
    end
  end

  def discover(domain_name) when is_binary(domain_name) do
    expire_leases(domain: domain_name)
    now = DateTime.utc_now()

    from(domain in Domain,
      join: connection in Connection,
      on: connection.organization_id == domain.organization_id,
      join: organization in Organization,
      on: organization.id == domain.organization_id,
      where: domain.domain == ^domain_name,
      where: domain.state == "verified",
      where: domain.discovery_enabled,
      where: domain.valid_until > ^now,
      where: not is_nil(connection.enabled_at),
      order_by: [asc: organization.name],
      select: organization
    )
    |> Repo.all(log: false)
    |> Enum.filter(&Features.enabled?/1)
  end

  def discover(_domain_name), do: []

  def discovery_available?(organization, domain_name) do
    Features.enabled?(organization) and
      Enum.any?(discover(domain_name), &(&1.id == organization.id))
  end

  def require_locked_discovery(organization, domain_name) do
    case require_locked_policy(organization, domain_name, :discovery_enabled) do
      {:ok, _domain} -> :ok
      {:error, _reason} = error -> error
    end
  end

  def require_locked_automatic_linking(organization, domain_name) do
    require_locked_policy(organization, domain_name, :automatic_linking_enabled)
  end

  defp require_locked_policy(organization, domain_name, policy) do
    now = DateTime.utc_now()

    domain =
      from(domain in Domain,
        where: domain.organization_id == ^organization.id,
        where: domain.domain == ^domain_name,
        lock: "FOR UPDATE"
      )
      |> Repo.one(log: false)

    cond do
      not Features.enabled?(organization) ->
        {:error, :feature_disabled}

      is_nil(domain) ->
        {:error, :domain_not_verified}

      domain.state != "verified" or not Map.fetch!(domain, policy) ->
        {:error, :domain_not_verified}

      is_nil(domain.valid_until) or DateTime.compare(domain.valid_until, now) != :gt ->
        {:error, :domain_not_verified}

      true ->
        {:ok, domain}
    end
  end

  def add(organization, value, audit: audit_data) do
    with :ok <- require_feature(organization),
         :ok <- require_admin(organization, audit_data.user),
         {:ok, canonical} <- DomainName.canonicalize(value) do
      Repo.transaction(fn ->
        organization = locked_organization!(organization.id)

        with :ok <- require_feature(organization),
             :ok <- require_locked_admin(organization, audit_data.user),
             :ok <- require_domain_capacity(organization) do
          attrs = %{
            organization_id: organization.id,
            domain: canonical,
            challenge: challenge(),
            challenge_generation: 1,
            state: "pending"
          }

          case Repo.insert(Domain.create_changeset(%Domain{}, attrs), log: false) do
            {:ok, domain} ->
              insert_audit!(audit_data, "sso.domain.add", {
                organization,
                %{domain: domain.domain}
              })

              domain

            {:error, changeset} ->
              Hexpm.RepoBase.rollback(changeset)
          end
        else
          {:error, reason} -> Hexpm.RepoBase.rollback(reason)
        end
      end)
      |> unwrap()
    end
  end

  def verify(organization, id, audit: audit_data) do
    with :ok <- require_feature(organization),
         :ok <- require_admin(organization, audit_data.user),
         %Domain{state: "pending"} = domain <- get(organization, id) do
      result = DomainResolver.impl().lookup_txt(challenge_name(domain))

      apply_check(domain, result, :manual, audit_data)
    else
      %Domain{} -> {:error, :reverification_required}
      nil -> {:error, :domain_not_found}
      {:error, _reason} = error -> error
    end
  end

  def rotate(organization, id, audit: audit_data) do
    with :ok <- require_feature(organization),
         :ok <- require_admin(organization, audit_data.user) do
      Repo.transaction(fn ->
        with :ok <- require_feature(organization),
             :ok <- require_locked_admin(organization, audit_data.user),
             %Domain{} = domain <- locked_domain(organization, id) do
          domain =
            domain
            |> change(
              challenge: challenge(),
              challenge_generation: domain.challenge_generation + 1,
              state: "pending",
              verified_at: nil,
              last_checked_at: nil,
              valid_until: nil,
              invalidated_at: nil,
              discovery_enabled: false,
              automatic_linking_enabled: false
            )
            |> Repo.update!(log: false)

          insert_audit!(audit_data, "sso.domain.reverify", {
            organization,
            %{domain: domain.domain, challenge_generation: domain.challenge_generation}
          })

          {domain, SSOContext.pending_domain_confirmation_ids(domain.id)}
        else
          nil -> Hexpm.RepoBase.rollback(:domain_not_found)
          {:error, reason} -> Hexpm.RepoBase.rollback(reason)
        end
      end)
      |> finalize_domain_change()
    end
  end

  def update_policy(organization, id, attrs, audit: audit_data) do
    with :ok <- require_feature(organization),
         :ok <- require_admin(organization, audit_data.user) do
      Repo.transaction(fn ->
        with :ok <- require_feature(organization),
             :ok <- require_locked_admin(organization, audit_data.user),
             %Domain{} = domain <- locked_domain(organization, id) do
          changeset = Domain.policy_changeset(domain, attrs)

          with :ok <- require_valid_lease_for_enablement(domain, changeset),
               :ok <- require_discovery_acknowledgement(domain, changeset, attrs) do
            case Repo.update(changeset, log: false) do
              {:ok, updated_domain} ->
                insert_audit!(audit_data, "sso.domain.policy", {
                  organization,
                  %{
                    domain: updated_domain.domain,
                    discovery_enabled: updated_domain.discovery_enabled,
                    automatic_linking_enabled: updated_domain.automatic_linking_enabled
                  }
                })

                confirmation_ids =
                  if domain.automatic_linking_enabled and
                       not updated_domain.automatic_linking_enabled do
                    SSOContext.pending_domain_confirmation_ids(domain.id)
                  else
                    []
                  end

                {updated_domain, confirmation_ids}

              {:error, changeset} ->
                Hexpm.RepoBase.rollback(changeset)
            end
          else
            {:error, reason} -> Hexpm.RepoBase.rollback(reason)
          end
        else
          nil -> Hexpm.RepoBase.rollback(:domain_not_found)
          {:error, reason} -> Hexpm.RepoBase.rollback(reason)
        end
      end)
      |> finalize_domain_change()
    end
  end

  def delete(organization, id, audit: audit_data) do
    with :ok <- require_feature(organization),
         :ok <- require_admin(organization, audit_data.user) do
      Repo.transaction(fn ->
        with :ok <- require_feature(organization),
             :ok <- require_locked_admin(organization, audit_data.user),
             %Domain{} = domain <- locked_domain(organization, id) do
          confirmation_ids = SSOContext.pending_domain_confirmation_ids(domain.id)
          Repo.delete!(domain, log: false)

          insert_audit!(audit_data, "sso.domain.delete", {
            organization,
            %{domain: domain.domain}
          })

          {domain, confirmation_ids}
        else
          nil -> Hexpm.RepoBase.rollback(:domain_not_found)
          {:error, reason} -> Hexpm.RepoBase.rollback(reason)
        end
      end)
      |> finalize_domain_change()
    end
  end

  def revalidate_due(opts \\ []) do
    if Features.available?() do
      expire_leases(limit: Keyword.get(opts, :expiration_limit, @default_expiration_limit))
      now = DateTime.utc_now()
      checked_before = DateTime.add(now, -@revalidation_interval_seconds, :second)
      limit = revalidation_limit(opts)
      organization_ids = enabled_organization_ids()
      due_query = due_domains_query(organization_ids, checked_before, now)
      due_count = Repo.aggregate(due_query, :count)
      domains = select_due_domains(due_query, limit)

      :telemetry.execute(
        [:hexpm, :sso, :domain_revalidation, :batch],
        %{
          due_count: due_count,
          selected_count: length(domains),
          remaining_count: max(due_count - length(domains), 0)
        },
        %{limit: limit}
      )

      Enum.map(domains, fn domain ->
        result = DomainResolver.impl().lookup_txt(challenge_name(domain))
        {domain.id, apply_check(domain, result, :background, nil)}
      end)
    else
      []
    end
  end

  def apply_check(%Domain{} = domain, result, source, audit_data \\ nil)
      when source in [:manual, :background] do
    Repo.transaction(fn ->
      current =
        from(candidate in Domain,
          where: candidate.id == ^domain.id,
          lock: "FOR UPDATE",
          preload: [:organization]
        )
        |> Repo.one()

      cond do
        is_nil(current) ->
          :stale

        current.challenge_generation != domain.challenge_generation ->
          :stale

        source == :background and current.state != "verified" ->
          :stale

        source == :background and require_feature(current.organization) != :ok ->
          :stale

        source == :manual and current.state != "pending" ->
          :stale

        source == :manual and require_feature(current.organization) != :ok ->
          Hexpm.RepoBase.rollback(:feature_disabled)

        source == :manual and require_locked_admin(current.organization, audit_data.user) != :ok ->
          Hexpm.RepoBase.rollback(:admin_required)

        true ->
          persist_result(current, result, source, audit_data)
      end
    end)
    |> unwrap()
    |> finalize_check()
  end

  def expire_leases(scope \\ [])

  def expire_leases(domain_name) when is_binary(domain_name) do
    expire_leases(domain: domain_name)
  end

  def expire_leases(scope) when is_list(scope) do
    now = DateTime.utc_now()
    limit = expiration_limit(scope)

    query =
      from(domain in Domain,
        where: domain.state == "verified",
        where: not is_nil(domain.valid_until),
        where: domain.valid_until <= ^now
      )

    query =
      case {Keyword.get(scope, :organization_id), Keyword.get(scope, :domain)} do
        {organization_id, _domain} when is_integer(organization_id) ->
          from(domain in query, where: domain.organization_id == ^organization_id)

        {_organization_id, domain_name} when is_binary(domain_name) ->
          from(domain in query, where: domain.domain == ^domain_name)

        _other ->
          query
      end

    due_count = Repo.aggregate(query, :count)

    {:ok, {expired_count, confirmation_ids}} =
      Repo.transaction(fn ->
        domains =
          query
          |> from(
            order_by: [asc: :id],
            limit: ^limit,
            lock: "FOR UPDATE",
            preload: [:organization]
          )
          |> Repo.all(log: false)

        confirmation_ids =
          Enum.flat_map(domains, fn domain ->
            confirmation_ids = SSOContext.pending_domain_confirmation_ids(domain.id)

            domain
            |> change(
              state: "invalid",
              valid_until: nil,
              invalidated_at: now,
              discovery_enabled: false,
              automatic_linking_enabled: false,
              updated_at: now
            )
            |> Repo.update!(log: false)
            |> insert_system_audit!("sso.domain.expire")

            confirmation_ids
          end)

        {length(domains), confirmation_ids}
      end)

    SSOContext.cancel_confirmations(confirmation_ids)

    :telemetry.execute(
      [:hexpm, :sso, :domain_expiration, :batch],
      %{
        due_count: due_count,
        selected_count: expired_count,
        remaining_count: max(due_count - expired_count, 0)
      },
      %{limit: limit, scope: expiration_scope(scope)}
    )

    {expired_count, nil}
  end

  def valid_lease?(%Domain{} = domain), do: require_valid_lease(domain) == :ok

  def challenge_name(%Domain{domain: domain}), do: "_hexpm-sso." <> domain

  defp persist_result(domain, {:ok, records}, source, audit_data) when is_list(records) do
    now = DateTime.utc_now()

    if Enum.all?(records, &is_binary/1) and domain.challenge in records do
      domain =
        domain
        |> change(
          state: "verified",
          verified_at: domain.verified_at || now,
          last_checked_at: now,
          valid_until: DateTime.add(now, @lease_seconds, :second),
          invalidated_at: nil
        )
        |> Repo.update!(log: false)

      maybe_audit_verification(domain, source, audit_data)
      {:verified, domain}
    else
      persist_definitive_failure(domain, source, now)
    end
  end

  defp persist_result(domain, {:definitive, _reason}, source, _audit_data) do
    persist_definitive_failure(domain, source, DateTime.utc_now())
  end

  defp persist_result(domain, {:transient, reason}, _source, _audit_data) do
    domain =
      domain
      |> change(last_checked_at: DateTime.utc_now())
      |> Repo.update!(log: false)

    {:transient, reason, domain}
  end

  defp persist_result(domain, _result, source, audit_data) do
    persist_result(domain, {:transient, :resolver_failure}, source, audit_data)
  end

  defp persist_definitive_failure(domain, :manual, now) do
    domain =
      domain
      |> change(last_checked_at: now)
      |> Repo.update!(log: false)

    {:not_verified, domain}
  end

  defp persist_definitive_failure(domain, :background, now) do
    confirmation_ids = SSOContext.pending_domain_confirmation_ids(domain.id)

    domain =
      domain
      |> change(
        state: "invalid",
        last_checked_at: now,
        valid_until: nil,
        invalidated_at: now,
        discovery_enabled: false,
        automatic_linking_enabled: false
      )
      |> Repo.update!(log: false)
      |> insert_system_audit!("sso.domain.invalidate")

    {:invalidated, domain, confirmation_ids}
  end

  defp maybe_audit_verification(_domain, :background, _audit_data), do: :ok

  defp maybe_audit_verification(domain, :manual, audit_data) do
    insert_audit!(audit_data, "sso.domain.verify", {
      domain.organization,
      %{domain: domain.domain, challenge_generation: domain.challenge_generation}
    })
  end

  defp require_valid_lease(%Domain{state: "verified", valid_until: %DateTime{} = valid_until}) do
    if DateTime.compare(valid_until, DateTime.utc_now()) == :gt,
      do: :ok,
      else: {:error, :domain_not_verified}
  end

  defp require_valid_lease(_domain), do: {:error, :domain_not_verified}

  defp require_valid_lease_for_enablement(domain, changeset) do
    enabling? =
      Enum.any?([:discovery_enabled, :automatic_linking_enabled], fn field ->
        not Map.fetch!(domain, field) and get_field(changeset, field)
      end)

    if enabling?, do: require_valid_lease(domain), else: :ok
  end

  defp require_discovery_acknowledgement(
         %Domain{discovery_enabled: true},
         _changeset,
         _attrs
       ),
       do: :ok

  defp require_discovery_acknowledgement(_domain, changeset, attrs) do
    enabling_discovery? =
      get_field(changeset, :discovery_enabled)

    acknowledged? =
      Ecto.Type.cast(:boolean, value(attrs, :discovery_disclosure_acknowledged)) == {:ok, true}

    if enabling_discovery? and not acknowledged?,
      do: {:error, :discovery_disclosure_acknowledgement_required},
      else: :ok
  end

  defp value(attrs, key), do: Map.get(attrs, key) || Map.get(attrs, to_string(key))

  defp enabled_organization_ids do
    Organization
    |> Repo.all(log: false)
    |> Enum.filter(&Features.enabled?/1)
    |> Enum.map(& &1.id)
  end

  defp due_domains_query([], _checked_before, _now) do
    from(domain in Domain, where: false)
  end

  defp due_domains_query(organization_ids, checked_before, now) do
    from(domain in Domain,
      where: domain.organization_id in ^organization_ids,
      where: domain.state == "verified",
      where: not is_nil(domain.valid_until) and domain.valid_until > ^now,
      where: is_nil(domain.last_checked_at) or domain.last_checked_at <= ^checked_before
    )
  end

  defp select_due_domains(_due_query, 0), do: []

  defp select_due_domains(due_query, limit) do
    ranked =
      from(domain in due_query,
        select: %{
          id: domain.id,
          organization_id: domain.organization_id,
          valid_until: domain.valid_until,
          urgency_rank: over(row_number(), :organization)
        },
        windows: [
          organization: [
            partition_by: domain.organization_id,
            order_by: [
              asc_nulls_first: domain.valid_until,
              asc_nulls_first: domain.last_checked_at,
              asc: domain.id
            ]
          ]
        ]
      )

    ids =
      from(domain in Ecto.Query.subquery(ranked),
        order_by: [
          asc: domain.urgency_rank,
          asc_nulls_first: domain.valid_until,
          asc: domain.organization_id,
          asc: domain.id
        ],
        limit: ^limit,
        select: domain.id
      )
      |> Repo.all(log: false)

    domains_by_id =
      from(domain in Domain, where: domain.id in ^ids, preload: [:organization])
      |> Repo.all(log: false)
      |> Map.new(&{&1.id, &1})

    Enum.map(ids, &Map.fetch!(domains_by_id, &1))
  end

  defp revalidation_limit(opts) do
    case Keyword.get(opts, :limit, @default_revalidation_limit) do
      limit when is_integer(limit) and limit > 0 -> min(limit, @default_revalidation_limit)
      _other -> 0
    end
  end

  defp expiration_limit(opts) do
    case Keyword.get(opts, :limit, @default_expiration_limit) do
      limit when is_integer(limit) and limit > 0 -> min(limit, @default_expiration_limit)
      _other -> 0
    end
  end

  defp expiration_scope(opts) do
    cond do
      is_integer(Keyword.get(opts, :organization_id)) -> :organization
      is_binary(Keyword.get(opts, :domain)) -> :domain
      true -> :global
    end
  end

  defp locked_domain(organization, id) do
    from(domain in Domain,
      where: domain.id == ^id and domain.organization_id == ^organization.id,
      lock: "FOR UPDATE",
      preload: [:organization]
    )
    |> Repo.one()
  end

  defp locked_organization!(id) do
    from(organization in Organization,
      where: organization.id == ^id,
      lock: "FOR UPDATE"
    )
    |> Repo.one!()
  end

  defp require_domain_capacity(organization) do
    count =
      Repo.aggregate(
        from(domain in Domain, where: domain.organization_id == ^organization.id),
        :count
      )

    if count < @max_domains_per_organization,
      do: :ok,
      else: {:error, :domain_limit_reached}
  end

  defp require_feature(organization) do
    if Features.enabled?(organization), do: :ok, else: {:error, :feature_disabled}
  end

  defp require_admin(organization, user) do
    if user && Organizations.get_role(organization, user) == "admin",
      do: :ok,
      else: {:error, :admin_required}
  end

  defp require_locked_admin(organization, user) do
    case user && locked_member(organization, user) do
      %OrganizationUser{role: "admin"} -> :ok
      _other -> {:error, :admin_required}
    end
  end

  defp locked_member(organization, user) do
    from(organization_user in OrganizationUser,
      where: organization_user.organization_id == ^organization.id,
      where: organization_user.user_id == ^user.id,
      lock: "FOR UPDATE"
    )
    |> Repo.one()
  end

  defp challenge do
    token = 32 |> :crypto.strong_rand_bytes() |> Base.url_encode64(padding: false)
    "hexpm-sso-verification=" <> token
  end

  defp insert_audit!(audit_data, action, params) do
    audit_data
    |> AuditLog.build(action, params)
    |> Repo.insert!()
  end

  defp insert_system_audit!(domain, action) do
    insert_audit!(
      %{
        user: domain.organization,
        auth_credential: nil,
        user_agent: "Hexpm SSO domain verifier",
        remote_ip: nil
      },
      action,
      {
        domain.organization,
        %{
          domain: domain.domain,
          challenge_generation: domain.challenge_generation
        }
      }
    )

    domain
  end

  defp finalize_domain_change({:ok, {domain, confirmation_ids}}) do
    SSOContext.cancel_confirmations(confirmation_ids)
    {:ok, domain}
  end

  defp finalize_domain_change({:error, reason}), do: {:error, reason}

  defp finalize_check({:ok, {:invalidated, domain, confirmation_ids}}) do
    SSOContext.cancel_confirmations(confirmation_ids)
    {:ok, {:invalidated, domain}}
  end

  defp finalize_check(result), do: result

  defp unwrap({:ok, result}), do: {:ok, result}
  defp unwrap({:error, reason}), do: {:error, reason}
end
