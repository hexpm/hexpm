defmodule Hexpm.WorkloadIdentities.WorkloadIdentity do
  use Hexpm.Schema

  alias Hexpm.WorkloadIdentities.TrustedRepository

  @providers ~w(github)
  @roles ~w(read write)
  @github_issuer "https://token.actions.githubusercontent.com"
  @repo_name_re ~r/\A[A-Za-z0-9._-]+\z/
  @repository_id_re ~r/\A[1-9][0-9]{0,18}\z/
  @package_name_re ~r/\A[a-z][a-z0-9_]*\z/
  @max_repositories 50

  schema "workload_identities" do
    field :provider, :string
    field :issuer, :string
    field :repository_owner, :string
    field :repository_owner_id, :string
    embeds_many :repositories, TrustedRepository, on_replace: :delete
    field :workflow, :string
    field :environment, :string, default: ""
    field :role, :string, default: "write"
    field :covers_private, :boolean, default: true
    field :packages, {:array, :string}
    field :covers_public, :boolean, default: false
    field :public_packages, {:array, :string}

    belongs_to :package, Package
    belongs_to :organization, Organization
    has_many :oauth_tokens, Hexpm.OAuth.Token

    timestamps()
  end

  def providers, do: @providers
  def github_issuer, do: @github_issuer

  def roles, do: @roles

  def max_repositories, do: @max_repositories

  @doc """
  Builds a new workload identity for a package or an organization.

  `"repositories"` takes the repositories as text, one per line or separated
  by commas, each a name optionally followed by its repository ID, or as a
  list of those entries or of `%{"name" => name, "id" => id}` maps. Hex reads
  the IDs from GitHub before the workload identity is stored, see
  `put_immutable_ids/3`.
  """
  def changeset(workload_identity, params, %Package{} = package) do
    params = normalize_params(params)

    workload_identity
    |> cast(params, ~w(provider repository_owner workflow environment)a)
    |> put_assoc(:package, package)
    |> validate_package_identity(params)
  end

  def changeset(workload_identity, params, %Organization{} = organization) do
    params = normalize_params(params)

    workload_identity
    |> cast(
      params,
      ~w(provider repository_owner workflow environment role
         covers_private packages covers_public public_packages)a
    )
    |> put_assoc(:organization, organization)
    |> validate_organization_identity(params, organization)
  end

  @doc """
  Changes a workload identity's repositories, workflow, environment and, for
  an organization's, the packages it covers. Its provider, repository owner
  and role stay, since changing them makes it a different workload identity.
  """
  def update_changeset(%__MODULE__{package_id: package_id} = workload_identity, params)
      when not is_nil(package_id) do
    params = normalize_params(params)

    workload_identity
    |> cast(params, ~w(workflow environment)a)
    |> validate_package_identity(params)
  end

  def update_changeset(
        %__MODULE__{organization: %Organization{} = organization} = workload_identity,
        params
      ) do
    params = normalize_params(params)

    workload_identity
    |> cast(
      params,
      ~w(workflow environment covers_private packages covers_public public_packages)a
    )
    |> validate_organization_identity(params, organization)
  end

  defp validate_package_identity(changeset, params) do
    changeset
    |> validate_required(~w(provider repository_owner workflow)a)
    |> validate_identity()
    |> cast_repositories(params)
    |> validate_some_repositories("is required")
  end

  defp validate_organization_identity(changeset, params, organization) do
    changeset
    |> validate_required(~w(provider repository_owner role)a)
    |> validate_inclusion(:role, @roles)
    |> validate_identity()
    |> cast_repositories(params)
    |> validate_organization_match()
    |> validate_coverage()
    |> validate_billing(organization)
  end

  defp normalize_params(params) do
    params
    |> Map.new(fn {key, value} -> {to_string(key), value} end)
    |> split_names("packages")
    |> split_names("public_packages")
  end

  defp validate_identity(changeset) do
    changeset
    |> validate_inclusion(:provider, @providers)
    |> update_change(:environment, &normalize_environment/1)
    |> update_change(:workflow, &normalize_workflow/1)
    |> update_change(:repository_owner, &normalize_name/1)
    |> validate_length(:repository_owner, count: :bytes, max: 39)
    |> validate_length(:workflow, count: :bytes, max: 255)
    |> validate_length(:environment, count: :codepoints, max: 255)
    |> validate_format(
      :repository_owner,
      ~r/\A[A-Za-z0-9](?:[A-Za-z0-9]|-(?=[A-Za-z0-9])){0,38}\z/
    )
    |> validate_format(:workflow, ~r/\A[A-Za-z0-9._-]+\.(yml|yaml)\z/)
    |> validate_format(:environment, ~r/\A[^\p{Cc}\p{Zl}\p{Zp}]*\z/u,
      message: "must not contain control characters or line breaks"
    )
    |> put_issuer()
  end

  # Without "repositories" in the params, an existing workload identity keeps
  # its repositories. A repository ID typed after a name is kept until Hex reads
  # the IDs from GitHub, which replace it for the repositories Hex can see.
  defp cast_repositories(changeset, params) do
    case Map.fetch(params, "repositories") do
      {:ok, value} ->
        owner = get_field(changeset, :repository_owner)

        case parse_repositories(value, owner) do
          {:ok, repositories} -> put_embed(changeset, :repositories, repositories)
          {:error, message} -> add_error(changeset, :repositories, message)
        end

      :error ->
        changeset
    end
  end

  defp parse_repositories(value, owner) do
    with {:ok, entries} <- repository_entries(value) do
      entries
      |> Enum.reduce_while({:ok, []}, fn entry, {:ok, acc} ->
        case parse_repository(entry, owner) do
          {:ok, repository} -> {:cont, {:ok, [repository | acc]}}
          {:error, message} -> {:halt, {:error, message}}
        end
      end)
      |> validate_repository_list()
    end
  end

  defp repository_entries(nil), do: {:ok, []}

  defp repository_entries(value) when is_binary(value),
    do: {:ok, String.split(value, ["\n", "\r", ","], trim: true) |> Enum.map(&String.trim/1)}

  defp repository_entries(value) when is_list(value), do: {:ok, value}
  defp repository_entries(_value), do: {:error, "must be a list of repositories"}

  defp parse_repository(%{"name" => name} = entry, owner) when is_binary(name),
    do: build_repository(name, entry["id"], owner)

  defp parse_repository(%{name: name} = entry, owner) when is_binary(name),
    do: build_repository(name, Map.get(entry, :id), owner)

  defp parse_repository(entry, owner) when is_binary(entry) do
    case String.split(entry) do
      [] -> {:ok, nil}
      [name] -> build_repository(name, nil, owner)
      [name, id] -> build_repository(name, id, owner)
      _ -> {:error, "must have one repository per line, a name and an optional repository ID"}
    end
  end

  defp parse_repository(_entry, _owner), do: {:error, "must be a list of repositories"}

  defp build_repository(name, id, owner) do
    name = name |> String.trim() |> String.downcase()
    id = if is_integer(id), do: Integer.to_string(id), else: id

    with {:ok, name} <- qualify_repository(name, owner),
         :ok <- validate_repository_id(name, id) do
      {:ok, %TrustedRepository{name: name, id: id}}
    end
  end

  # The owner is validated on its own, so a name is only checked once the
  # owner is valid.
  defp qualify_repository(name, owner) when is_binary(owner) and owner != "" do
    short_name =
      case String.split(name, "/") do
        [^owner, short_name] -> short_name
        [short_name] -> short_name
        _ -> nil
      end

    cond do
      is_nil(short_name) ->
        {:error, "#{name} must be a repository of #{owner}"}

      byte_size(short_name) > 100 or not Regex.match?(@repo_name_re, short_name) ->
        {:error, "#{name} must be a valid GitHub repository name"}

      true ->
        {:ok, "#{owner}/#{short_name}"}
    end
  end

  defp qualify_repository(name, _owner), do: {:ok, name}

  defp validate_repository_id(_name, id) when id in [nil, ""], do: :ok

  defp validate_repository_id(name, id) when is_binary(id) do
    if Regex.match?(@repository_id_re, id),
      do: :ok,
      else: {:error, "#{name} must be followed by a numeric repository ID"}
  end

  defp validate_repository_id(name, _id),
    do: {:error, "#{name} must be followed by a numeric repository ID"}

  defp validate_repository_list({:ok, repositories}) do
    repositories =
      repositories
      |> Enum.reject(&is_nil/1)
      |> Enum.reverse()
      |> Enum.map(&%{&1 | id: if(&1.id == "", do: nil, else: &1.id)})

    duplicates =
      repositories
      |> Enum.frequencies_by(& &1.name)
      |> Enum.filter(fn {_name, count} -> count > 1 end)
      |> Enum.map(&elem(&1, 0))
      |> Enum.sort()

    cond do
      duplicates != [] ->
        {:error, "must list each repository once, not #{Enum.join(duplicates, ", ")} again"}

      length(repositories) > @max_repositories ->
        {:error, "must be at most #{@max_repositories} repositories"}

      true ->
        {:ok, repositories}
    end
  end

  defp validate_repository_list(error), do: error

  defp validate_some_repositories(changeset, message) do
    if Keyword.has_key?(changeset.errors, :repositories) or
         get_field(changeset, :repositories) != [] do
      changeset
    else
      add_error(changeset, :repositories, message)
    end
  end

  # A read workload identity may leave the workflow empty to match every
  # workflow in its repositories, or list no repositories to match every
  # repository its owner has. Either reaches as far as an organization key
  # stored as a GitHub secret. A write workload identity names both.
  defp validate_organization_match(changeset) do
    case {get_field(changeset, :role), get_field(changeset, :repositories)} do
      {"read", []} ->
        any_repository(changeset)

      {"read", _repositories} ->
        if get_field(changeset, :workflow),
          do: changeset,
          else: put_change(changeset, :workflow, "")

      _ ->
        changeset
        |> validate_required([:workflow], message: "is required for the write role")
        |> validate_some_repositories("are required for the write role")
    end
  end

  # Whoever creates a repository also names its workflows and environments, so
  # neither narrows a workload identity that matches every repository. The fields keep
  # what was typed when they aren't empty, so a resubmitted form doesn't turn
  # into a workload identity for every repository.
  defp any_repository(changeset) do
    if Keyword.has_key?(changeset.errors, :repositories) do
      changeset
    else
      fields = [:workflow, :environment]
      changeset = Enum.reduce(fields, changeset, &validate_empty(&2, &1))

      if Enum.any?(fields, &Keyword.has_key?(changeset.errors, &1)),
        do: changeset,
        else: put_change(changeset, :workflow, "")
    end
  end

  defp validate_empty(changeset, field) do
    if get_field(changeset, field) in [nil, ""] do
      changeset
    else
      add_error(changeset, field, "must be empty when every repository matches")
    end
  end

  # A read workload identity fetches every package in the organization's
  # repository, and public packages need no credentials to fetch. The form
  # keeps the hidden checkboxes and package lists when the role goes back to
  # read.
  defp validate_coverage(changeset) do
    case get_field(changeset, :role) do
      "write" ->
        changeset
        |> validate_required([:covers_private, :covers_public])
        |> validate_covers_any()
        |> validate_private_packages()
        |> validate_public_packages()

      _role ->
        changeset
        |> put_change(:covers_private, true)
        |> put_change(:packages, nil)
        |> put_change(:covers_public, false)
        |> put_change(:public_packages, nil)
    end
  end

  defp validate_covers_any(changeset) do
    if get_field(changeset, :covers_private) == true or
         get_field(changeset, :covers_public) == true do
      changeset
    else
      add_error(changeset, :covers_private, "select private packages, public packages or both")
    end
  end

  # An identity without private coverage stores an empty list, which covers
  # no package for code that only reads the list.
  defp validate_private_packages(changeset) do
    if get_field(changeset, :covers_private) == true,
      do: validate_package_names(changeset, :packages, &valid_package_name?/1),
      else: put_change(changeset, :packages, [])
  end

  # Listed public packages must already exist and be owned by the organization,
  # which is checked against the database, so their names only need to be
  # names a package can have had, including ones created before today's rules.
  defp validate_public_packages(changeset) do
    if get_field(changeset, :covers_public) == true,
      do: validate_package_names(changeset, :public_packages, &existing_package_name?/1),
      else: put_change(changeset, :public_packages, nil)
  end

  defp validate_package_names(changeset, field, valid?) do
    case get_field(changeset, field) do
      nil ->
        changeset

      names ->
        if Enum.all?(names, valid?) do
          put_change(changeset, field, names |> Enum.uniq() |> Enum.sort())
        else
          add_error(changeset, field, "must be valid package names")
        end
    end
  end

  # Fetching from the organization's repository and publishing to it need an
  # active subscription. Public packages don't, the same as for an
  # organization key. An existing workload identity can still be changed
  # without one, for example to stop trusting a repository, as long as the
  # change doesn't turn private packages on.
  defp validate_billing(changeset, organization) do
    cond do
      Organization.billing_active?(organization) ->
        changeset

      changeset.data.id && not turns_on_private?(changeset) ->
        changeset

      get_field(changeset, :role) == "read" ->
        add_error(changeset, :role, "needs an active billing subscription")

      get_field(changeset, :covers_private) == true ->
        add_error(
          changeset,
          :covers_private,
          "private packages need an active billing subscription"
        )

      true ->
        changeset
    end
  end

  defp turns_on_private?(changeset) do
    get_field(changeset, :role) == "write" and get_field(changeset, :covers_private) == true and
      changeset.data.covers_private != true
  end

  @doc """
  Adds an error for listed public package names that aren't public packages
  the organization owns.
  """
  def validate_public_owner(changeset, []), do: changeset

  def validate_public_owner(changeset, not_owned) do
    add_error(
      changeset,
      :public_packages,
      "must be public packages the organization owns, not #{Enum.join(not_owned, ", ")}"
    )
  end

  @doc """
  Whether an organization workload identity publishes, and may create, the
  package with this name in the organization's repository.
  """
  def covers_private_package?(
        %__MODULE__{role: "write", covers_private: true, packages: packages} = identity,
        name
      )
      when is_binary(name) do
    not is_nil(identity.organization_id) and (is_nil(packages) or name in packages)
  end

  def covers_private_package?(_workload_identity, _name), do: false

  @doc """
  Whether an organization workload identity publishes the public package with
  this name while the organization owns it. The list being empty covers every
  public package the organization owns.
  """
  def covers_public_package?(
        %__MODULE__{role: "write", covers_public: true, public_packages: packages} = identity,
        name
      )
      when is_binary(name) do
    not is_nil(identity.organization_id) and (is_nil(packages) or name in packages)
  end

  def covers_public_package?(_workload_identity, _name), do: false

  @doc """
  Whether a package can be created with this name.
  """
  def valid_package_name?(name) do
    is_binary(name) and byte_size(name) in 2..255 and Regex.match?(@package_name_re, name) and
      name not in Package.reserved_names()
  end

  defp existing_package_name?(name) do
    is_binary(name) and byte_size(name) in 1..255
  end

  # The form sends one string per list, so names may be separated by commas or
  # whitespace. No names means every package.
  defp split_names(params, key) do
    case params[key] do
      value when is_binary(value) ->
        case String.split(value, [",", " ", "\n", "\r", "\t"], trim: true) do
          [] -> Map.put(params, key, nil)
          names -> Map.put(params, key, names)
        end

      [] ->
        Map.put(params, key, nil)

      _ ->
        params
    end
  end

  @doc """
  Pins the GitHub IDs Hex read for the repository owner and the repositories.

  `resolved` has the owner's ID, and for each repository name the ID Hex read,
  nil for a repository Hex can't see, and whether it's public. A repository
  Hex can't see keeps the ID typed after its name. A repository the workload
  identity already trusts keeps the ID it was pinned to, so one deleted and
  created again under the same name is refused instead of trusted.
  """
  def put_immutable_ids(changeset, resolved) do
    pinned = Map.new(changeset.data.repositories, &{&1.name, &1.id})

    changeset
    |> put_owner_id(to_string(resolved.repository_owner_id))
    |> put_repository_ids(resolved.repositories, pinned)
    |> validate_public_environment(public_repositories(changeset, resolved.repositories))
  end

  defp put_owner_id(%{data: %{repository_owner_id: nil}} = changeset, owner_id),
    do: put_change(changeset, :repository_owner_id, owner_id)

  defp put_owner_id(%{data: %{repository_owner_id: owner_id}} = changeset, owner_id),
    do: changeset

  defp put_owner_id(changeset, _owner_id) do
    add_error(
      changeset,
      :repository_owner,
      "is a different GitHub account than when the workload identity was added"
    )
  end

  defp put_repository_ids(changeset, resolved, pinned) do
    {repositories, errors} =
      changeset
      |> get_field(:repositories)
      |> Enum.map_reduce([], fn repository, errors ->
        case pin_repository(repository, resolved[repository.name], pinned[repository.name]) do
          {:ok, repository} -> {repository, errors}
          {:error, message} -> {repository, [message | errors]}
        end
      end)

    case errors do
      [] ->
        put_embed(changeset, :repositories, repositories)

      # Each error is prepended, so the errors end up in the typed order.
      errors ->
        Enum.reduce(errors, changeset, &add_error(&2, :repositories, &1))
    end
  end

  # A repository recreated under the same name is a different repository, so
  # a workload identity never trusts a repository without its pinned ID. Hex
  # can't read the ID of a repository it can't see, so the admin types it.
  defp pin_repository(repository, %{moved: true}, _pinned) do
    {:error,
     "#{repository.name} was renamed or transferred on GitHub. " <>
       "Replace it with the repository's new name"}
  end

  defp pin_repository(repository, %{id: id}, pinned) when not is_nil(id) do
    id = to_string(id)

    if pinned in [nil, id] do
      {:ok, %{repository | id: id}}
    else
      {:error,
       "#{repository.name} was deleted and created again on GitHub since it was added. " <>
         "Remove it and save, then add it again"}
    end
  end

  defp pin_repository(repository, _resolved, pinned) when is_binary(pinned) do
    if repository.id in [nil, pinned] do
      {:ok, %{repository | id: pinned}}
    else
      {:error,
       "#{repository.name} has repository ID #{pinned}. " <>
         "Remove it and save, then add it again with the new ID"}
    end
  end

  defp pin_repository(%{id: id} = repository, _resolved, nil) when is_binary(id),
    do: {:ok, repository}

  defp pin_repository(repository, _resolved, nil) do
    {:error,
     "#{repository.name} needs its repository ID after the name, because Hex can't see it on GitHub"}
  end

  defp public_repositories(changeset, resolved) do
    changeset
    |> get_field(:repositories)
    |> Enum.filter(&match?(%{public: true}, resolved[&1.name]))
    |> Enum.map(& &1.name)
  end

  # GitHub offers environments in public repositories on every plan, and their
  # protection rules are the only check GitHub runs before a job gets a token.
  # Private repositories only have environments on paid GitHub plans.
  defp validate_public_environment(changeset, []), do: changeset

  defp validate_public_environment(changeset, public) do
    if get_field(changeset, :role) == "write" and get_field(changeset, :environment) in [nil, ""] do
      verb = if length(public) == 1, do: "is", else: "are"

      add_error(
        changeset,
        :environment,
        "is required because #{Enum.join(public, ", ")} #{verb} public"
      )
    else
      changeset
    end
  end

  defp put_issuer(changeset) do
    case get_field(changeset, :provider) do
      "github" -> put_change(changeset, :issuer, @github_issuer)
      _ -> changeset
    end
  end

  # The workflow keeps its casing because it is matched exactly against the OIDC
  # claims. Owner and repository are downcased because the GitHub namespace is
  # itself case-insensitive. The environment keeps the casing the owner typed
  # and is compared case-insensitively.
  defp normalize_environment(nil), do: ""
  defp normalize_environment(value), do: String.trim(value)

  defp normalize_workflow(nil), do: nil
  defp normalize_workflow(workflow), do: workflow |> String.trim() |> Path.basename()

  defp normalize_name(nil), do: nil
  defp normalize_name(name), do: name |> String.trim() |> String.downcase()
end
