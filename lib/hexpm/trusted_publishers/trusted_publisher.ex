defmodule Hexpm.TrustedPublishers.TrustedPublisher do
  use Hexpm.Schema

  @providers ~w(github)
  @github_issuer "https://token.actions.githubusercontent.com"
  @repo_name_re ~r/\A[A-Za-z0-9._-]+\z/

  schema "trusted_publishers" do
    field :provider, :string
    field :issuer, :string
    field :repository_owner, :string
    field :repository_owner_id, :string
    field :repository_id, :string
    field :repository, :string
    field :workflow, :string
    field :environment, :string, default: ""

    belongs_to :package, Package
    has_many :oauth_tokens, Hexpm.OAuth.Token

    timestamps()
  end

  def providers, do: @providers
  def github_issuer, do: @github_issuer

  def changeset(trusted_publisher, params, package) do
    trusted_publisher
    |> cast(params, ~w(provider repository_owner repository repository_id workflow environment)a)
    |> put_assoc(:package, package)
    |> validate_required(~w(provider repository_owner repository workflow)a)
    |> validate_inclusion(:provider, @providers)
    |> update_change(:environment, &normalize_environment/1)
    |> update_change(:workflow, &normalize_workflow/1)
    |> update_change(:repository_owner, &normalize_name/1)
    |> update_change(:repository, &normalize_name/1)
    |> qualify_repository()
    |> validate_format(
      :repository_owner,
      ~r/\A[A-Za-z0-9](?:[A-Za-z0-9]|-(?=[A-Za-z0-9])){0,38}\z/
    )
    |> validate_repository()
    |> validate_format(:workflow, ~r/\A[A-Za-z0-9._-]+\.(yml|yaml)\z/)
    |> validate_format(:repository_id, ~r/\A[1-9][0-9]*\z/)
    |> put_issuer()
    |> unique_constraint(:repository,
      name: :trusted_publishers_package_config_unique,
      message: "trusted publisher already configured for this package"
    )
  end

  def put_immutable_ids(changeset, attrs) do
    changeset
    |> put_change(:repository_owner_id, to_string(attrs.repository_owner_id))
    |> put_repository_id(Map.get(attrs, :repository_id))
    |> validate_required([:repository_owner_id])
  end

  # A repository recreated under the same name is a different repository, so a
  # publisher is never stored without a pinned repository id. Hex cannot read
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

  # Workflow and environment keep their casing because they are matched exactly
  # against the OIDC claims. Owner and repository are downcased because the
  # GitHub namespace is itself case-insensitive.
  defp normalize_environment(nil), do: ""
  defp normalize_environment(value), do: String.trim(value)

  defp normalize_workflow(nil), do: nil
  defp normalize_workflow(workflow), do: workflow |> String.trim() |> Path.basename()

  defp normalize_name(nil), do: nil
  defp normalize_name(name), do: name |> String.trim() |> String.downcase()
end
