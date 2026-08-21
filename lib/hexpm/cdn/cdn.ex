defmodule Hexpm.CDN do
  @moduledoc """
  Fastly surrogate-key purging.

  Callers purge through `purge/3`, which enqueues a `Hexpm.CDN.PurgeWorker`
  job; the job sends the purge, sends it again two seconds later (the shield
  race Fastly documents), waits for propagation, then verifies the objects
  the caller named against the CDN and re-purges while they still serve the
  old ETag. `purge_key/2` and `verify/2` are the raw operations the job runs.
  """

  @type service :: atom
  @type key :: String.t()
  @type ip :: <<_::32>>
  @type mask :: 0..32

  @typedoc """
  An object to check after purging: the CDN must serve `url` with `etag`,
  or with a 404 when `etag` is `nil`. `repository` names the organization
  whose private repository the object belongs to; the check then carries a
  short-lived token the edge accepts for that repository.
  """
  @type target :: %{
          required(:url) => String.t(),
          required(:etag) => String.t() | nil,
          optional(:repository) => String.t() | nil
        }

  @callback purge_key(service, [key]) :: :ok | {:error, term}
  @callback verify(service, [target]) :: [{target, :ok | {:error, term}}]
  @callback public_ips() :: [{ip, mask}]

  defp impl(), do: Application.get_env(:hexpm, :cdn_impl)

  @doc "Sends one purge request for the given surrogate keys."
  def purge_key(service, keys), do: impl().purge_key(service, List.wrap(keys))

  @doc "Checks that `service` serves every target, see `t:target/0`."
  def verify(service, targets), do: impl().verify(service, targets)

  def public_ips(), do: impl().public_ips()

  @doc """
  Enqueues a purge of `keys` on `service`.

  `:verify` lists the objects to check afterwards, see `t:target/0`. Runs in
  the caller's transaction when there is one, so a rolled-back write never
  purges.
  """
  @spec purge(service, key | [key], keyword) :: Oban.Job.t()
  def purge(service, keys, opts \\ []) do
    keys = keys |> List.wrap() |> Enum.uniq()

    verify =
      opts
      |> Keyword.get(:verify, [])
      |> Enum.map(fn target -> Map.new(target, fn {k, v} -> {to_string(k), v} end) end)

    %{"service" => Atom.to_string(service), "keys" => keys, "verify" => verify}
    |> Hexpm.CDN.PurgeWorker.new()
    |> Oban.insert!()
  end
end
