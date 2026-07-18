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
    policy: 3,
    diff: 4
  }

  def init(_reason, opts) do
    if url = System.get_env("HEXPM_DATABASE_URL") do
      pool_size_env = System.get_env("HEXPM_DATABASE_POOL_SIZE")
      pool_size = if pool_size_env, do: String.to_integer(pool_size_env), else: opts[:pool_size]

      opts =
        opts
        |> Keyword.put(:url, url)
        |> Keyword.put(:pool_size, pool_size)

      {:ok, opts}
    else
      {:ok, opts}
    end
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

defimpl Plug.Exception, for: Hexpm.WriteInReadOnlyMode do
  def status(_exception), do: 503
  def actions(_exception), do: []
end
