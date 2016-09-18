defmodule HexWeb.Release do
  use HexWeb.Web, :model

  schema "releases" do
    field :version, HexWeb.Version
    field :checksum, :string
    field :has_docs, :boolean, default: false
    timestamps()

    belongs_to :package, Package
    has_many :requirements, Requirement, on_replace: :delete
    has_many :daily_downloads, Download
    has_one :downloads, ReleaseDownload
    embeds_one :meta, ReleaseMetadata, on_replace: :delete
  end

  defp changeset(release, :create, params) do
    changeset(release, :update, params)
    |> unique_constraint(:version, name: "releases_package_id_version_key", message: "has already been published")
  end

  defp changeset(release, :update, params) do
    cast(release, params, ~w(version))
    |> cast_embed(:meta, required: true)
    |> Requirement.build_all
    |> validate_version(:version)
  end

  def build(package, params, checksum) do
    build_assoc(package, :releases)
    |> changeset(:create, params)
    |> put_change(:checksum, String.upcase(checksum))
  end

  def update(release, params, checksum) do
    release
    |> changeset(:update, params)
    |> put_change(:checksum, String.upcase(checksum))
    |> validate_editable(:update, false)
  end

  def delete(release, opts \\ []) do
    force? = Keyword.get(opts, :force, false)
    change(release)
    |> validate_editable(:delete, force?)
  end

  defp validate_editable(changeset, action, force)
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

  defp editable?(release) do
    inserted_at =
      release.inserted_at
      |> NaiveDateTime.to_erl
      |> to_secs

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

  def latest_version(nil), do: nil
  def latest_version([]), do: nil
  def latest_version(versions) do
    Enum.reduce(versions, fn version, latest ->
      if Version.compare(version, latest) == :lt do
        latest
      else
        version
      end
    end)
  end

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

  def recent(count) do
    from(r in HexWeb.Release,
         order_by: [desc: r.inserted_at],
         join: p in assoc(r, :package),
         limit: ^count,
         select: {p.name, r.version, r.inserted_at, p.meta})
  end
end

defimpl Phoenix.Param, for: HexWeb.Release do
  def to_param(release) do
    to_string(release.version)
  end
end
