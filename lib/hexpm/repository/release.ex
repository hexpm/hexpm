defmodule Hexpm.Repository.Release do
  use Hexpm.Schema

  @derive {HexpmWeb.Stale, assocs: [:requirements, :downloads]}
  @one_hour 60 * 60
  @one_day @one_hour * 24

  schema "releases" do
    field :version, Hexpm.Version
    field :inner_checksum, :binary
    field :outer_checksum, :binary
    field :has_docs, :boolean, default: false
    timestamps()

    belongs_to :package, Package
    belongs_to(:publisher, User, on_replace: :nilify)
    has_many :requirements, Requirement, on_replace: :delete
    has_many :daily_downloads, Download
    has_many :package_report_releases, PackageReportRelease
    has_many :package_reports, through: [:package_report_releases, :package_report]
    has_one :downloads, ReleaseDownload

    embeds_one :meta, ReleaseMetadata, on_replace: :delete
    embeds_one :retirement, ReleaseRetirement, on_replace: :delete
  end

  defp changeset(
         release,
         :create,
         params,
         package,
         publisher,
         inner_checksum,
         outer_checksum,
         replace?
       ) do
    changeset(
      release,
      :update,
      params,
      package,
      publisher,
      inner_checksum,
      outer_checksum,
      replace?
    )
    |> unique_constraint(
      :version,
      name: "releases_package_id_version_key",
      message: "has already been published"
    )
  end

  defp changeset(
         release,
         :update,
         params,
         package,
         publisher,
         inner_checksum,
         outer_checksum,
         replace?
       ) do
    cast(release, params, ~w(version)a)
    |> cast_embed(:meta, required: true)
    |> validate_version(:version)
    |> validate_editable(:update, false, replace?)
    |> put_change(:inner_checksum, inner_checksum)
    |> put_change(:outer_checksum, outer_checksum)
    |> put_assoc(:publisher, publisher)
    |> Requirement.build_all(package)
  end

  def build(package, publisher, params, inner_checksum, outer_checksum, replace? \\ true) do
    build_assoc(package, :releases)
    |> changeset(:create, params, package, publisher, inner_checksum, outer_checksum, replace?)
  end

  def update(release, publisher, params, inner_checksum, outer_checksum, replace? \\ true) do
    changeset(
      release,
      :update,
      params,
      release.package,
      publisher,
      inner_checksum,
      outer_checksum,
      replace?
    )
  end

  def delete(release, opts \\ []) do
    force? = Keyword.get(opts, :force, false)

    change(release)
    |> validate_editable(:delete, force?, true)
  end

  def retire(release, params) do
    cast_embed(
      cast(release, params, []),
      :retirement,
      required: true,
      with: &ReleaseRetirement.changeset(&1, &2, public: true)
    )
  end

  def reported_retire(release) do
    change(
      release,
      %{
        retirement: %{
          reason: "report",
          message: "security vulnerability reported"
        }
      }
    )
    |> cast_embed(
      :retirement,
      required: true,
      with: &ReleaseRetirement.changeset(&1, &2, public: false)
    )
  end

  def unretire(release) do
    change(release)
    |> put_embed(:retirement, nil)
  end

  defp validate_editable(changeset, _action, true = _force?, _replace?) do
    changeset
  end

  defp validate_editable(changeset, action, _force?, replace?) do
    cond do
      is_nil(changeset.data.inserted_at) ->
        changeset

      not editable?(changeset.data) ->
        add_error(changeset, :inserted_at, editable_error_message(action))

      replace? not in [true, "true"] ->
        message = "must include the --replace flag to update an existing release"
        add_error(changeset, :inserted_at, message)

      true ->
        changeset
    end
  end

  defp editable_error_message(:update) do
    "can only modify a release up to one hour after publication"
  end

  defp editable_error_message(:delete),
    do: "can only delete a release up to one hour after publication"

  defp editable?(release) do
    release.package.repository.id != 1 or
      within_seconds?(release.inserted_at, @one_hour) or
      within_seconds?(release.package.inserted_at, @one_day)
  end

  defp within_seconds?(datetime, within_seconds) do
    at =
      datetime
      |> NaiveDateTime.to_erl()
      |> erl_to_seconds()

    now = erl_to_seconds(:calendar.universal_time())
    now - at <= within_seconds
  end

  defp erl_to_seconds(datetime), do: :calendar.datetime_to_gregorian_seconds(datetime)

  def package_versions(packages) do
    package_ids = Enum.map(packages, & &1.id)

    from(
      r in Release,
      where: r.package_id in ^package_ids,
      group_by: r.package_id,
      select: {r.package_id, fragment("array_agg(?)", r.version)}
    )
  end

  def latest_version(nil, _opts), do: nil

  def latest_version(releases, opts) do
    only_stable? = Keyword.fetch!(opts, :only_stable)
    unstable_fallback? = Keyword.get(opts, :unstable_fallback, false)
    with_docs? = Keyword.get(opts, :with_docs)

    with_docs_releases =
      if with_docs? do
        Enum.filter(releases, & &1.has_docs)
      else
        releases
      end

    stable_releases =
      if only_stable? do
        Enum.filter(with_docs_releases, &(to_version(&1).pre == []))
      else
        with_docs_releases
      end

    if stable_releases == [] and unstable_fallback? do
      latest(releases)
    else
      latest(stable_releases)
    end
  end

  defp latest([]), do: nil

  defp latest(releases) do
    Enum.reduce(releases, fn release, latest ->
      if compare(release, latest) == :lt do
        latest
      else
        release
      end
    end)
  end

  defp compare(release1, release2) do
    Version.compare(to_version(release1), to_version(release2))
  end

  defp to_version(%Release{version: version}), do: to_version(version)
  defp to_version(%Version{} = version), do: version
  defp to_version(version) when is_binary(version), do: Version.parse!(version)

  def all(package) do
    assoc(package, :releases)
  end

  def sort(releases) do
    Enum.sort(releases, &(Version.compare(&1.version, &2.version) == :gt))
  end

  def requirements(release) do
    from(
      req in assoc(release, :requirements),
      join: package in assoc(req, :dependency),
      join: repo in assoc(package, :repository),
      order_by: [repo.name, package.name],
      select: %{req | name: package.name, repository: repo.name}
    )
  end

  def count() do
    from(r in Release, select: count(r.id))
  end

  def recent(repository, count) do
    from(
      r in Hexpm.Repository.Release,
      join: p in assoc(r, :package),
      where: p.repository_id == ^repository.id,
      order_by: [desc: r.inserted_at],
      limit: ^count,
      select: {p.name, r.version, r.inserted_at, p.meta}
    )
  end

  def downloads_for_last_n_days(release_id, num_of_days) do
    date_start = Date.add(Date.utc_today(), -1 * num_of_days)
    from(d in downloads_by_period(release_id, :day), where: d.day >= ^date_start)
  end

  def downloads_by_period(release_id, filter) do
    from(d in Download, where: d.release_id == ^release_id)
    |> Download.query_filter(filter)
  end
end

defimpl Phoenix.Param, for: Hexpm.Repository.Release do
  def to_param(release) do
    to_string(release.version)
  end
end
