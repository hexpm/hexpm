defmodule Hexpm.Repository.Release do
  use Hexpm.Web, :schema

  schema "releases" do
    field :version, Hexpm.Version
    field :checksum, :string
    field :has_docs, :boolean, default: false
    timestamps()

    belongs_to :package, Package
    has_many :requirements, Requirement, on_replace: :delete
    has_many :daily_downloads, Download
    has_one :downloads, ReleaseDownload

    embeds_one :meta, ReleaseMetadata, on_replace: :delete
    embeds_one :retirement, ReleaseRetirement, on_replace: :delete
  end

  defp changeset(release, :create, params, checksum) do
    changeset(release, :update, params, checksum)
    |> unique_constraint(:version, name: "releases_package_id_version_key", message: "has already been published")
  end

  defp changeset(release, :update, params, checksum) do
    cast(release, params, ~w(version))
    |> cast_embed(:meta, required: true)
    |> validate_version(:version)
    |> validate_editable(:update, false)
    |> put_change(:checksum, String.upcase(checksum))
    |> Requirement.build_all()
  end

  def build(package, params, checksum) do
    build_assoc(package, :releases)
    |> changeset(:create, params, checksum)
  end

  def update(release, params, checksum) do
    changeset(release, :update, params, checksum)
  end

  def delete(release, opts \\ []) do
    force? = Keyword.get(opts, :force, false)
    change(release)
    |> validate_editable(:delete, force?)
  end

  def retire(release, params) do
    cast(release, params, [])
    |> cast_embed(:retirement, required: true)
  end

  def unretire(release) do
    change(release)
    |> put_embed(:retirement, nil)
  end

  defp validate_editable(changeset, _action, true), do: changeset
  defp validate_editable(changeset, action, false) do
    if editable?(changeset.data) do
      changeset
    else
      add_error(changeset, :inserted_at, editable_error_message(action))
    end
  end

  defp editable_error_message(:update), do: "can only modify a release up to one hour after creation"
  defp editable_error_message(:delete), do: "can only delete a release up to one hour after creation"

  defp editable?(%Release{inserted_at: nil}), do: true
  defp editable?(release) do
    inserted_at =
      release.inserted_at
      |> NaiveDateTime.to_erl()
      |> to_secs()

    now = to_secs(:calendar.universal_time)
    now - inserted_at <= 3600
  end

  defp to_secs(datetime), do: :calendar.datetime_to_gregorian_seconds(datetime)

  def package_versions(packages) do
    package_ids = Enum.map(packages, & &1.id)
    from(r in Release,
         where: r.package_id in ^package_ids,
         group_by: r.package_id,
         select: {r.package_id, fragment("array_agg(?)", r.version)})
  end

  def latest_version(nil, _opts), do: nil
  def latest_version(releases, opts) do
    only_stable? = Keyword.fetch!(opts, :only_stable)
    unstable_fallback? = Keyword.get(opts, :unstable_fallback, false)

    stable_releases = if only_stable? do
      Enum.filter(releases, &(to_version(&1).pre == []))
    else
      releases
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
    from(req in assoc(release, :requirements),
         join: p in assoc(req, :dependency),
         order_by: p.name,
         select: %{req | name: p.name})
  end

  def count do
    from(r in Release, select: count(r.id))
  end

  def recent(repository, count) do
    from(r in Hexpm.Repository.Release,
      join: p in assoc(r, :package),
      where: p.repository_id == ^repository.id,
      order_by: [desc: r.inserted_at],
      limit: ^count,
      select: {p.name, r.version, r.inserted_at, p.meta}
    )
  end
end

defimpl Phoenix.Param, for: Hexpm.Repository.Release do
  def to_param(release) do
    to_string(release.version)
  end
end
