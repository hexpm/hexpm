defmodule Hexpm.Accounts.OrganizationDomains do
  @moduledoc """
  Domains an organization has proved it controls, by publishing a TXT record
  containing a token only that organization was given.

  Verification is not permanent. Just-in-time membership admits people on the
  strength of these, so a domain that has changed hands has to stop verifying:
  `recheck_all/1` runs periodically and clears any domain whose record has gone.
  """

  use Hexpm.Context

  alias Hexpm.Accounts.OrganizationDomain

  require Logger

  @dns_timeout 5_000
  @recheck_after_seconds 24 * 60 * 60

  def all(organization) do
    Repo.all(
      from(domain in OrganizationDomain,
        where: domain.organization_id == ^organization.id,
        order_by: domain.domain
      )
    )
  end

  def all_verified(organization) do
    Repo.all(
      from(domain in OrganizationDomain,
        where: domain.organization_id == ^organization.id,
        where: not is_nil(domain.verified_at),
        order_by: domain.domain
      )
    )
  end

  def get(organization, id) do
    Repo.one(
      from(domain in OrganizationDomain,
        where: domain.organization_id == ^organization.id,
        where: domain.id == ^id
      )
    )
  end

  @doc """
  Whether the organization has proved it controls the domain the address is on.
  Only exact matches count: verifying example.com does not verify a subdomain of
  it, because control of one does not follow from control of the other.
  """
  def verified_for_email?(organization, email) do
    case OrganizationDomain.from_email(email) do
      nil ->
        false

      domain ->
        Repo.exists?(
          from(row in OrganizationDomain,
            where: row.organization_id == ^organization.id,
            where: row.domain == ^domain,
            where: not is_nil(row.verified_at)
          )
        )
    end
  end

  def add(organization, params, added_by, audit: audit_data) do
    changeset =
      OrganizationDomain.changeset(%OrganizationDomain{}, %{
        "organization_id" => organization.id,
        "added_by_user_id" => added_by && added_by.id,
        "domain" => params["domain"],
        "verification_token" => random_token()
      })

    Multi.new()
    |> Multi.insert(:domain, changeset)
    |> audit(audit_data, "organization.domain.add", &{organization, &1.domain})
    |> Repo.transaction()
    |> case do
      {:ok, %{domain: domain}} -> {:ok, domain}
      {:error, :domain, changeset, _changes} -> {:error, changeset}
    end
  end

  def remove(organization, domain, audit: audit_data) do
    Multi.new()
    |> Multi.delete(:domain, domain)
    |> audit(audit_data, "organization.domain.remove", {organization, domain})
    |> Repo.transaction()
    |> case do
      {:ok, %{domain: domain}} -> {:ok, domain}
      {:error, :domain, changeset, _changes} -> {:error, changeset}
    end
  end

  @doc """
  Looks for the domain's TXT record and records what it found. Returns
  `{:ok, domain}` when the record is there and `{:error, :record_not_found}`
  when it is not, in both cases having stamped `last_checked_at`.
  """
  def verify(organization, domain, audit: audit_data) do
    now = DateTime.utc_now()

    case published?(domain) do
      {:ok, true} ->
        Multi.new()
        |> Multi.update(:domain, OrganizationDomain.verified_changeset(domain, now))
        |> audit(audit_data, "organization.domain.verify", {organization, domain})
        |> Repo.transaction()
        |> case do
          {:ok, %{domain: domain}} -> {:ok, domain}
          {:error, :domain, changeset, _changes} -> {:error, changeset}
        end

      {:ok, false} ->
        Repo.update!(change(domain, last_checked_at: now))
        {:error, :record_not_found}

      :error ->
        {:error, :lookup_failed}
    end
  end

  @doc """
  Re-checks every verified domain that has not been looked at for a day and
  clears the ones whose record has gone. Returns the number cleared.
  """
  def recheck_all(now \\ DateTime.utc_now()) do
    cutoff = DateTime.add(now, -@recheck_after_seconds, :second)

    Repo.all(
      from(domain in OrganizationDomain,
        where: not is_nil(domain.verified_at),
        where: is_nil(domain.last_checked_at) or domain.last_checked_at < ^cutoff,
        preload: [:organization]
      )
    )
    |> Enum.count(&recheck(&1, now))
  end

  # A resolver that cannot answer is not the same as a record that is gone.
  # Treating them alike would let one bad minute of DNS unverify every domain
  # hexpm knows, and nothing re-checks a domain once it is cleared, so every
  # organization would need a human. A failed lookup leaves both the
  # verification and `last_checked_at` alone, so the next run tries again.
  defp recheck(domain, now) do
    case published?(domain) do
      :error ->
        Logger.warning("[domains] could not look up #{domain.domain}, leaving it verified")
        false

      {:ok, true} ->
        Repo.update!(change(domain, last_checked_at: now))
        false

      {:ok, false} ->
        unverify(domain, now)
    end
  end

  defp unverify(domain, now) do
    Repo.transaction(fn ->
      Repo.update!(OrganizationDomain.unverified_changeset(domain, now))

      Repo.insert!(
        AuditLog.build(
          AuditLogs.system(domain.organization),
          "organization.domain.unverify",
          {domain.organization, domain}
        )
      )
    end)

    Logger.warning(
      "[domains] #{domain.domain} no longer verifies for #{domain.organization.name}"
    )

    true
  end

  defp published?(domain) do
    expected = OrganizationDomain.record_value(domain)

    with {:ok, records} <- txt_records(domain.domain) do
      {:ok, Enum.any?(records, &Plug.Crypto.secure_compare(&1, expected))}
    end
  end

  # `:error` means the resolver did not answer. An empty list means it answered
  # and there is no matching record, which is a real absence.
  defp txt_records(domain) do
    task =
      Task.Supervisor.async_nolink(Hexpm.Tasks, fn ->
        resolver().lookup(String.to_charlist(domain))
      end)

    case Task.yield(task, dns_timeout()) do
      {:ok, records} when is_list(records) ->
        {:ok, records}

      {:exit, _reason} ->
        :error

      nil ->
        Task.shutdown(task, :brutal_kill)
        :error
    end
  end

  defp resolver do
    Application.get_env(:hexpm, :domain_dns_resolver, __MODULE__.Resolver)
  end

  defp dns_timeout do
    Application.get_env(:hexpm, :domain_dns_timeout, @dns_timeout)
  end

  defp random_token do
    24 |> :crypto.strong_rand_bytes() |> Base.url_encode64(padding: false)
  end
end

defmodule Hexpm.Accounts.OrganizationDomains.Resolver do
  @doc """
  TXT records for the domain, or a raise when the resolver could not answer.

  `:inet_res.lookup/3` cannot be used here: it flattens a timeout, SERVFAIL and
  "no such record" into the same empty list, and the caller has to tell the last
  one apart from the first two. The trailing dot makes the query absolute, so a
  resolver search list cannot turn `example.com` into a lookup of some
  `example.com.internal`.
  """
  def lookup(domain) do
    case :inet_res.resolve(domain ++ ~c".", :in, :txt) do
      {:ok, message} ->
        # A TXT record longer than 255 bytes arrives split into several strings
        # that have to be joined back together before comparing.
        for {:dns_rr, _, :txt, :in, _, _, strings, _, _, _} <- :inet_dns.msg(message, :anlist),
            do: IO.iodata_to_binary(strings)

      {:error, {:nxdomain, _message}} ->
        []

      {:error, reason} ->
        raise "DNS lookup for #{domain} failed: #{inspect(reason)}"
    end
  end
end
