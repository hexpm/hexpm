defmodule HexWeb.Release do
  use HexWeb.Web, :model
  alias HexWeb.Utils

  @timestamps_opts [usec: true]

  schema "releases" do
    field :version, HexWeb.Version
    field :checksum, :string
    field :meta, :map
    field :has_docs, :boolean, default: false
    timestamps

    belongs_to :package, Package
    has_many :requirements, Requirement
    has_many :daily_downloads, Download
    has_one :downloads, ReleaseDownload
  end

  @meta_types %{
    "app"         => :string,
    "build_tools" => {:array, :string},
    "elixir"      => :string
  }

  @meta_fields Map.keys(@meta_types)

  @meta_fields_required ~w(app build_tools)

  defp validate_meta(changeset, field) do
    validate_change(changeset, field, fn _field, meta ->
      type_errors =
        Enum.flat_map(@meta_types, fn {sub_field, type} ->
          type(sub_field, Map.get(meta, sub_field), type)
        end)

      req_errors =
        Enum.flat_map(@meta_fields_required, fn field ->
          if Map.has_key?(meta, field) do
            []
          else
            [{field, :missing}]
          end
        end)

      errors = req_errors ++ type_errors

      if errors == [],
          do: [],
        else: [{field, errors}]
    end)
  end

  defp changeset(release, :create, params) do
    changeset(release, :update, params)
    |> validate_unique(:version, scope: [:package_id], on: HexWeb.Repo)
  end

  defp changeset(release, :update, params) do
    cast(release, params, ~w(version meta), [])
    |> validate_version(:version)
    |> update_change(:meta, &Map.take(&1, @meta_fields))
    |> validate_meta(:meta)
  end

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
    if editable?(release) or force? do
      # TODO: Delete tarball from S3
      HexWeb.Repo.delete!(release)
      :ok
    else
      {:error, [inserted_at: "can only delete a release up to one hour after creation"]}
    end
  end

  defp editable?(release) do
    inserted_at =
      Ecto.DateTime.to_erl(release.inserted_at)
      |> :calendar.datetime_to_gregorian_seconds

    now =
      :calendar.universal_time
      |> :calendar.datetime_to_gregorian_seconds

    now - inserted_at <= 3600
  end

  def latest_versions(packages) do
    package_ids = Enum.map(packages, & &1.id)

    query =
           from r in Release,
         where: r.package_id in ^package_ids,
      group_by: r.package_id,
        select: {r.package_id, fragment("array_agg(?)", r.version)}

    result = HexWeb.Repo.all(query)
    Enum.into(result, %{}, fn {id, versions} ->
      {id, latest_version(versions)}
    end)
  end

  def latest_version([]) do
    nil
  end

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
    HexWeb.Repo.all(assoc(package, :releases))
    |> Enum.map(& %{&1 | package: package})
    |> sort
  end

  def sort(releases) do
    releases
    |> Enum.sort(&(Version.compare(&1.version, &2.version) == :gt))
  end

  def get(package, version) do
    from(r in assoc(package, :releases), where: r.version == ^version, limit: 1)
    |> HexWeb.Repo.one
    |> Utils.maybe(& %{&1 | package: package})
    |> Utils.maybe(& %{&1 | requirements: requirements(&1)})
  end

  def requirements(release) do
    from(req in assoc(release, :requirements),
         join: p in assoc(req, :dependency),
         select: {p.name, req.app, req.requirement, req.optional},
         order_by: p.name)
    |> HexWeb.Repo.all
  end

  def count do
    HexWeb.Repo.all(from(r in Release, select: fragment("count(?)", r.id)))
    |> List.first
  end

  def recent(count) do
    from(r in HexWeb.Release,
         order_by: [desc: r.inserted_at],
         join: p in assoc(r, :package),
         limit: ^count,
         select: {r.version, p.name})
    |> HexWeb.Repo.all
  end

  def docs_url(release) do
    HexWeb.Utils.docs_url([release.package.name, to_string(release.version)])
  end
end
