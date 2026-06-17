defmodule Hexpm.RepoHelpers do
  defmacro defwrite({name, _meta, params}) do
    quote do
      def unquote(name)(unquote_splicing(params)) do
        write_mode!()
        Hexpm.RepoBase.unquote(name)(unquote_splicing(params_to_args(params)))
      end
    end
  end

  defp params_to_args(params) do
    Enum.map(params, fn
      {:\\, _meta, [arg, _default]} -> arg
      arg -> arg
    end)
  end
end

defmodule Hexpm.Repo do
  import Hexpm.RepoHelpers
  alias Hexpm.RepoBase

  defdelegate aggregate(queryable, aggregate, opts \\ []), to: RepoBase
  defdelegate aggregate(queryable, aggregate, field, opts), to: RepoBase
  defdelegate all(queryable, opts \\ []), to: RepoBase
  defdelegate exists?(queryable, opts \\ []), to: RepoBase
  defdelegate get_by!(queryable, clauses, opts \\ []), to: RepoBase
  defdelegate get_by(queryable, clauses, opts \\ []), to: RepoBase
  defdelegate get!(queryable, id, opts \\ []), to: RepoBase
  defdelegate get(queryable, id, opts \\ []), to: RepoBase
  defdelegate one!(queryable, opts \\ []), to: RepoBase
  defdelegate one(queryable, opts \\ []), to: RepoBase
  defdelegate preload(structs_or_struct_or_nil, preloads, opts \\ []), to: RepoBase

  defwrite(advisory_xact_lock(key, opts \\ []))
  defwrite(try_advisory_xact_lock?(key, opts \\ []))
  defwrite(try_advisory_lock?(key, opts \\ []))
  defwrite(advisory_unlock(key, opts \\ []))
  defwrite(delete_all(queryable, opts \\ []))
  defwrite(delete!(struct_or_changeset, opts \\ []))
  defwrite(delete(struct_or_changeset, opts \\ []))
  defwrite(insert_all(schema_or_source, entries_or_query, opts \\ []))
  defwrite(insert_or_update(changeset, opts \\ []))
  defwrite(insert!(struct_or_changeset, opts \\ []))
  defwrite(insert(struct_or_changeset, opts \\ []))
  defwrite(query!(sql, params \\ [], opts \\ []))
  defwrite(query(sql, params \\ [], opts \\ []))
  defwrite(refresh_view(schema, opts \\ []))
  defwrite(rollback(value))
  defwrite(transaction(fun_or_multi, opts \\ []))
  defwrite(update_all(queryable, opts \\ []))
  defwrite(update!(changeset, opts \\ []))
  defwrite(update(changeset, opts \\ []))

  def write_mode?() do
    not Application.get_env(:hexpm, :read_only_mode, false)
  end

  def write_mode!() do
    unless write_mode?() do
      raise Hexpm.WriteInReadOnlyMode
    end
  end
end

defmodule Hexpm.RepoBase do
  use Ecto.Repo,
    otp_app: :hexpm,
    adapter: Ecto.Adapters.Postgres

  @advisory_locks %{
    registry: 1,
    vulnerability_updater: 2,
    policy: 3
  }

  def init(_reason, opts) do
    if url = System.get_env("HEXPM_DATABASE_URL") do
      pool_size_env = System.get_env("HEXPM_DATABASE_POOL_SIZE")
      pool_size = if pool_size_env, do: String.to_integer(pool_size_env), else: opts[:pool_size]
      ca_cert = System.get_env("HEXPM_DATABASE_CA_CERT")
      client_key = System.get_env("HEXPM_DATABASE_CLIENT_KEY")
      client_cert = System.get_env("HEXPM_DATABASE_CLIENT_CERT")

      ssl_opts =
        if ca_cert do
          [
            verify: :verify_peer,
            cacerts: [decode_cert(ca_cert)],
            key: decode_key(client_key),
            cert: decode_cert(client_cert),
            # Cloud SQL's server certificate (GOOGLE_MANAGED_INTERNAL_CA) has a Common
            # Name but no Subject Alternative Name. OTP's TLS hostname verification
            # requires a SAN and rejects such certificates with
            # {:bad_cert, {:hostname_check_failed, :missing_subject_altnames}}, so we use
            # verify-CA semantics: the certificate chain is still validated against the
            # pinned instance CA above and the mTLS client certificate is still presented,
            # but the hostname is not matched. (customize_hostname_check does not help —
            # the missing-SAN check short-circuits before the match_fun runs.)
            server_name_indication: :disable
          ]
        end

      opts =
        opts
        |> Keyword.put(:url, url)
        |> Keyword.put(:pool_size, pool_size)
        |> then(fn opts ->
          if ssl_opts, do: Keyword.put(opts, :ssl, ssl_opts), else: opts
        end)

      {:ok, opts}
    else
      {:ok, opts}
    end
  end

  defp decode_cert(cert) do
    [{:Certificate, der, _}] = :public_key.pem_decode(cert)
    der
  end

  defp decode_key(cert) do
    [{:RSAPrivateKey, key, :not_encrypted}] = :public_key.pem_decode(cert)
    {:RSAPrivateKey, key}
  end

  def refresh_view(schema, opts \\ [])

  def refresh_view(schema, opts) when is_atom(schema) do
    source = schema.__schema__(:source)
    refresh_view(source, opts)
  end

  def refresh_view(source, opts) when is_binary(source) do
    concurrently = if Keyword.get(opts, :concurrently, true), do: "CONCURRENTLY"
    query = ~s(REFRESH MATERIALIZED VIEW #{concurrently} "#{source}")

    {:ok, _} = Hexpm.Repo.query(query, [], opts)
    :ok
  end

  def advisory_xact_lock(key, opts \\ []) do
    unless skip_advisory_locks?() do
      {sub_key, opts} = Keyword.pop(opts, :sub_key)

      {sql, params} =
        if sub_key do
          {"SELECT pg_advisory_xact_lock($1, $2)", [Map.fetch!(@advisory_locks, key), sub_key]}
        else
          {"SELECT pg_advisory_xact_lock($1)", [Map.fetch!(@advisory_locks, key)]}
        end

      %Postgrex.Result{} = query!(sql, params, opts)
    end

    :ok
  end

  def try_advisory_xact_lock?(key, opts \\ []) do
    if skip_advisory_locks?() do
      true
    else
      %Postgrex.Result{rows: [[result]]} =
        query!(
          "SELECT pg_try_advisory_xact_lock($1)",
          [Map.fetch!(@advisory_locks, key)],
          opts
        )

      result
    end
  end

  def try_advisory_lock?(key, opts \\ []) do
    if skip_advisory_locks?() do
      true
    else
      %Postgrex.Result{rows: [[result]]} =
        query!(
          "SELECT pg_try_advisory_lock($1)",
          [Map.fetch!(@advisory_locks, key)],
          opts
        )

      result
    end
  end

  def advisory_unlock(key, opts \\ []) do
    if skip_advisory_locks?() do
      :ok
    else
      %Postgrex.Result{rows: [[true]]} =
        query!(
          "SELECT pg_advisory_unlock($1)",
          [Map.fetch!(@advisory_locks, key)],
          opts
        )

      :ok
    end
  end

  defp skip_advisory_locks?() do
    Application.get_env(:hexpm, :skip_advisory_locks, false)
  end
end

defmodule Hexpm.WriteInReadOnlyMode do
  defexception []

  def message(_) do
    "tried to write in read-only mode"
  end
end
