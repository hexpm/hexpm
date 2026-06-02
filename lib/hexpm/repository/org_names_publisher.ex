defmodule Hexpm.Repository.OrgNamesPublisher do
  @moduledoc false

  import Ecto.Query, only: [from: 2]
  require Logger

  alias Hexpm.Accounts.Organization
  alias Hexpm.Repo

  @bucket_key "org_names.csv"
  @content_type "text/csv"
  @cache_control "public, max-age=300"
  @public_org_name "hexpm"

  @doc """
  Builds the org-names CSV (one organization name per line, excluding the
  public `hexpm` organization) and uploads it to `:docs_bucket` as
  `org_names.csv`. Fastly Compute reads this file to redirect
  `ORG.hexdocs.pm -> ORG.hexorgs.pm`.
  """
  @spec publish() :: :ok
  def publish do
    names = list_org_names()
    csv = Enum.map_intersperse(names, "\n", & &1)

    opts = [
      content_type: @content_type,
      cache_control: @cache_control,
      meta: [{"surrogate-key", "org_names"}]
    ]

    Hexpm.Store.put(:docs_bucket, @bucket_key, IO.iodata_to_binary(csv), opts)
    Logger.info("Published #{@bucket_key} with #{length(names)} orgs")
    :ok
  end

  defp list_org_names do
    Repo.all(
      from o in Organization,
        where: o.name != ^@public_org_name,
        order_by: o.name,
        select: o.name
    )
  end
end
