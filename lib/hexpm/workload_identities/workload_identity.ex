defmodule Hexpm.WorkloadIdentities.WorkloadIdentity do
  use Hexpm.Schema

  @providers ~w(github)
  @roles ~w(read write)
  @github_issuer "https://token.actions.githubusercontent.com"
  @repo_name_re ~r/\A[A-Za-z0-9._-]+\z/
  @package_name_re ~r/\A[a-z][a-z0-9_]*\z/

  schema "workload_identities" do
    field :provider, :string
    field :issuer, :string
    field :repository_owner, :string
    field :repository_owner_id, :string
    field :repository_id, :string
    field :repository, :string
    field :workflow, :string
    field :environment, :string, default: ""
    field :role, :string, default: "write"
    field :packages, {:array, :string}

    belongs_to :package, Package
    belongs_to :organization, Organization
    has_many :oauth_tokens, Hexpm.OAuth.Token

    timestamps()
  end

  def providers, do: @providers
  def github_issuer, do: @github_issuer

  def roles, do: @roles

  def changeset(workload_identity, params, %Package{} = package) do
    workload_identity
    |> cast(params, ~w(provider repository_owner repository repository_id workflow environment)a)
    |> put_assoc(:package, package)
    |> validate_required(~w(provider repository_owner repository workflow)a)
    |> validate_identity()
    |> unique_constraint(:repository,
      name: :workload_identities_package_config_unique,
      message: "workload identity already configured for this package"
    )
  end

  def changeset(workload_identity, params, %Organization{} = organization) do
    params = split_packages(params)

    workload_identity
    |> cast(
      params,
      ~w(provider repository_owner repository repository_id workflow environment role packages)a
    )
    |> put_assoc(:organization, organization)
    |> validate_required(~w(provider repository_owner role)a)
    |> validate_inclusion(:role, @roles)
    |> validate_identity()
    |> validate_organization_match()
    |> validate_packages()
    |> unique_constraint(:repository,
      name: :workload_identities_organization_config_unique,
      message: "workload identity already configured for this organization"
    )
  end

  defp validate_identity(changeset) do
    changeset
    |> validate_inclusion(:provider, @providers)
    |> update_change(:environment, &normalize_environment/1)
    |> update_change(:workflow, &normalize_workflow/1)
    |> update_change(:repository_owner, &normalize_name/1)
    |> update_change(:repository, &normalize_name/1)
    |> qualify_repository()
    |> validate_length(:repository_owner, count: :bytes, max: 39)
    |> validate_length(:repository, count: :bytes, max: 140)
    |> validate_length(:repository_id, count: :bytes, max: 19)
    |> validate_length(:workflow, count: :bytes, max: 255)
    |> validate_length(:environment, count: :codepoints, max: 255)
    |> validate_format(
      :repository_owner,
      ~r/\A[A-Za-z0-9](?:[A-Za-z0-9]|-(?=[A-Za-z0-9])){0,38}\z/
    )
    |> validate_repository()
    |> validate_format(:workflow, ~r/\A[A-Za-z0-9._-]+\.(yml|yaml)\z/)
    |> validate_format(:repository_id, ~r/\A[1-9][0-9]*\z/)
    |> put_issuer()
  end

  # A read workload identity may leave the workflow empty to match every workflow in the
  # repository, or the repository empty to match every repository its owner
  # has. Either reaches as far as an organization key stored as a GitHub secret.
  # A write workload identity names both.
  defp validate_organization_match(changeset) do
    case {get_field(changeset, :role), get_field(changeset, :repository)} do
      {"read", nil} ->
        any_repository(changeset)

      {"read", _repository} ->
        if get_field(changeset, :workflow),
          do: changeset,
          else: put_change(changeset, :workflow, "")

      _ ->
        validate_required(changeset, [:repository, :workflow],
          message: "is required for the write role"
        )
    end
  end

  # Whoever creates a repository also names its workflows and environments, so
  # neither narrows a workload identity that matches every repository. The fields keep
  # what was typed when they aren't empty, so a resubmitted form doesn't turn
  # into a workload identity for every repository.
  defp any_repository(changeset) do
    fields = [:workflow, :environment, :repository_id]
    changeset = Enum.reduce(fields, changeset, &validate_empty(&2, &1))

    if Enum.any?(fields, &Keyword.has_key?(changeset.errors, &1)) do
      changeset
    else
      changeset
      |> put_change(:repository, "")
      |> put_change(:repository_id, "")
      |> put_change(:workflow, "")
    end
  end

  defp validate_empty(changeset, field) do
    if get_field(changeset, field) in [nil, ""] do
      changeset
    else
      add_error(changeset, field, "must be empty when every repository matches")
    end
  end

  defp validate_packages(changeset) do
    case {get_field(changeset, :role), get_field(changeset, :packages)} do
      {_role, nil} ->
        changeset

      {"write", packages} ->
        if Enum.all?(packages, &valid_package_name?/1) do
          put_change(changeset, :packages, packages |> Enum.uniq() |> Enum.sort())
        else
          add_error(changeset, :packages, "must be valid package names")
        end

      # The form keeps the hidden package list when the role goes back to read.
      {_role, _packages} ->
        put_change(changeset, :packages, nil)
    end
  end

  @doc """
  Whether a package can be created with this name.
  """
  def valid_package_name?(name) do
    is_binary(name) and byte_size(name) in 2..255 and Regex.match?(@package_name_re, name) and
      name not in Package.reserved_names()
  end

  @doc """
  The repository's name without its owner, as the forms take it.
  """
  def repository_name(nil), do: nil
  def repository_name(repository), do: repository |> String.split("/") |> List.last()

  # The form sends one string, so names may be separated by commas or
  # whitespace. No names means every package.
  defp split_packages(params) do
    params = Map.new(params, fn {key, value} -> {to_string(key), value} end)

    case params["packages"] do
      value when is_binary(value) ->
        case String.split(value, [",", " ", "\n", "\r", "\t"], trim: true) do
          [] -> Map.put(params, "packages", nil)
          names -> Map.put(params, "packages", names)
        end

      [] ->
        Map.put(params, "packages", nil)

      _ ->
        params
    end
  end

  def put_immutable_ids(changeset, attrs) do
    changeset
    |> put_change(:repository_owner_id, to_string(attrs.repository_owner_id))
    |> put_repository_id(Map.get(attrs, :repository_id))
    |> validate_required([:repository_owner_id])
  end

  # A repository recreated under the same name is a different repository, so a
  # workload identity is never stored without a pinned repository id. Hex cannot read
  # that id for a repository it cannot see, so the client supplies it instead.
  defp put_repository_id(changeset, nil) do
    if get_field(changeset, :repository_id) do
      changeset
    else
      add_error(
        changeset,
        :repository_id,
        "is required when Hex cannot resolve the repository on GitHub"
      )
    end
  end

  defp put_repository_id(changeset, repository_id) do
    put_change(changeset, :repository_id, to_string(repository_id))
  end

  defp put_issuer(changeset) do
    case get_field(changeset, :provider) do
      "github" -> put_change(changeset, :issuer, @github_issuer)
      _ -> changeset
    end
  end

  defp qualify_repository(changeset) do
    owner = get_field(changeset, :repository_owner)
    repository = get_field(changeset, :repository)

    if is_binary(owner) and is_binary(repository) and not String.contains?(repository, "/") do
      put_change(changeset, :repository, "#{owner}/#{repository}")
    else
      changeset
    end
  end

  defp validate_repository(changeset) do
    owner = get_field(changeset, :repository_owner)
    repository = get_field(changeset, :repository)

    if is_nil(owner) or is_nil(repository) do
      changeset
    else
      case String.split(repository, "/") do
        [^owner, name] ->
          if Regex.match?(@repo_name_re, name) do
            changeset
          else
            invalid_repository(changeset)
          end

        _ ->
          invalid_repository(changeset)
      end
    end
  end

  defp invalid_repository(changeset) do
    add_error(
      changeset,
      :repository,
      "must be a valid GitHub repository owned by repository_owner"
    )
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
