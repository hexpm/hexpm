defmodule HexWeb.Release do
  use HexWeb.Web, :model

  @timestamps_opts [usec: true]

  schema "releases" do
    field :version, HexWeb.Version
    field :checksum, :string
    field :has_docs, :boolean, default: false
    timestamps

    belongs_to :package, Package
    has_many :requirements, Requirement
    has_many :daily_downloads, Download
    has_one :downloads, ReleaseDownload
    embeds_one :meta, ReleaseMetadata, on_replace: :delete
  end

  defp changeset(release, :create, params) do
    changeset(release, :update, params)
    |> unique_constraint(:version, name: "releases_package_id_version_key", message: "has already been published")
  end

  defp changeset(release, :update, params) do
    cast(release, params, ~w(version), [])
    |> cast_embed(:meta, required: true)
    |> validate_version(:version)
  end

  # TODO: Leave this in until we have multi
  def create(package, params, checksum) do
    changeset =
      build_assoc(package, :releases)
      |> changeset(:create, params)
      |> put_change(:checksum, String.upcase(checksum))

    HexWeb.Repo.transaction(fn ->
      case HexWeb.Repo.insert(changeset) do
        {:ok, release} ->
          requirements = params["requirements"] || %{}

          case Requirement.create_all(release, requirements) do
            {:ok, reqs} ->
              %{release | requirements: reqs, package: package}
            {:error, errors} ->
              HexWeb.Repo.rollback([requirements: errors])
          end
        {:error, changeset} ->
          HexWeb.Repo.rollback(changeset.errors)
      end
    end)
  end

  # TODO: Leave this in until we have multi
  def update(release, params, checksum) do
    if editable?(release) do
      changeset =
        changeset(release, :update, params)
        |> put_change(:checksum, String.upcase(checksum))

      HexWeb.Repo.transaction(fn ->
        case HexWeb.Repo.update(changeset) do
          {:ok, release} ->
            HexWeb.Repo.delete_all(assoc(release, :requirements))

            release = HexWeb.Repo.update!(changeset)
            requirements = params["requirements"] || %{}

            case HexWeb.Requirement.create_all(release, requirements) do
              {:ok, reqs} ->
                %{release | requirements: reqs}
              {:error, errors} ->
                HexWeb.Repo.rollback([requirements: errors])
            end
          {:error, changeset} ->
            HexWeb.Repo.rollback(changeset.errors)
        end
      end)
    else
      {:error, [inserted_at: "can only modify a release up to one hour after creation"]}
    end
  end

  def delete(release, opts \\ []) do
    force? = Keyword.get(opts, :force, false)
    change(release) |> validate_editable(force?)
  end

  defp validate_editable(changeset, true), do: changeset
  defp validate_editable(changeset, false) do
    validate_change(changeset, :inserted_at, fn _field, _value ->
      if editable?(changeset.model) do
        []
      else
        [inserted_at: "can only delete a release up to one hour after creation"]
      end
    end)
  end

  defp editable?(release) do
    inserted_at =
      release.inserted_at
      |> Ecto.DateTime.to_erl
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
    # TODO: ecto should support %{req | ...} syntax
    from(req in assoc(release, :requirements),
         join: p in assoc(req, :dependency),
         order_by: p.name,
         select: %{id: req.id, release_id: req.release_id, dependency_id: p.id,
                   name: p.name, app: req.app, requirement: req.requirement,
                   optional: req.optional})
  end

  def count do
    from(r in Release,
         select: count(r.id))
  end

  def recent(count) do
    from(r in HexWeb.Release,
         order_by: [desc: r.inserted_at],
         join: p in assoc(r, :package),
         limit: ^count,
         select: {r.version, p.name})
  end
end

defimpl Phoenix.Param, for: HexWeb.Release do
  def to_param(release) do
    to_string(release.version)
  end
end
