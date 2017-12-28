defmodule Hexpm.Repository.Repositories do
  use Hexpm.Web, :context

  def all_public() do
    Repo.all(from(r in Repository, where: r.public))
  end

  def all_by_user(user) do
    Repo.all(assoc(user, :repositories))
  end

  def get(name, preload \\ []) do
    Repo.get_by(Repository, name: name)
    |> Repo.preload(preload)
  end

  def access?(%Repository{public: false}, nil, _role) do
    false
  end

  def access?(%Repository{public: false} = repository, user, role) do
    Repo.one!(Repository.has_access(repository, user, role))
  end

  def create(user, params, [audit: audit_data]) do
    multi =
      Multi.new()
      |> Multi.insert(:repository, Repository.changeset(%Repository{}, params))
      |> Multi.merge(fn %{repository: repository} ->
        repository_user = %RepositoryUser{
          repository_id: repository.id,
          user_id: user.id,
          role: "admin"
        }

        Multi.insert(Multi.new(), :repository_user, Repository.add_member(repository_user, %{}))
      end)
      |> audit(audit_data, "repository.create", fn %{repository: repository} -> repository end)

    case Repo.transaction(multi) do
      {:ok, result} ->
        {:ok, result.repository}
      {:error, :repository, changeset, _} ->
        {:error, changeset}
    end
  end

  def add_member(repository, username, params, [audit: audit_data]) do
    if user = Users.get(username, [:emails]) do
      repository_user = %RepositoryUser{repository_id: repository.id, user_id: user.id}

      multi =
        Multi.new()
        |> Multi.insert(:repository_user, Repository.add_member(repository_user, params))
        |> audit(audit_data, "repository.member.add", {repository, user})

      case Repo.transaction(multi) do
        {:ok, result} ->
          send_invite_email(repository, user)
          {:ok, result.repository_user}
        {:error, :repository_user, changeset, _} ->
          {:error, changeset}
      end
    else
      {:error, :unknown_user}
    end
  end

  def remove_member(repository, username, [audit: audit_data]) do
    if user = Users.get(username) do
      count = Repo.aggregate(assoc(repository, :repository_users), :count, :id)

      if count == 1 do
        {:error, :last_member}
      else
        repository_user = Repo.get_by(assoc(repository, :repository_users), user_id: user.id)

        if repository_user do
          {:ok, _result} =
            Multi.new()
            |> Multi.delete(:repository_user, repository_user)
            |> audit(audit_data, "repository.member.remove", {repository, user})
            |> Repo.transaction()
        end

        :ok
      end
    else
      {:error, :unknown_user}
    end
  end

  def change_role(repository, username, params, [audit: audit_data]) do
    user = Users.get(username)
    repository_users = Repo.all(assoc(repository, :repository_users))
    repository_user = Enum.find(repository_users, &(&1.user_id == user.id))
    number_admins = Enum.count(repository_users, &(&1.role == "admin"))

    cond do
      !repository_user ->
        {:error, :unknown_user}
      repository_user.role == "admin" and number_admins == 1 ->
        {:error, :last_admin}

      true ->
        multi =
          Multi.new()
          |> Multi.update(:repository_user, Repository.change_role(repository_user, params))
          |> audit(audit_data, "repository.member.role", {repository, user, params["role"]})

        case Repo.transaction(multi) do
          {:ok, result} ->
            {:ok, result.repository_user}
          {:error, :repository_user, changeset, _} ->
            {:error, changeset}
        end
    end
  end

  defp send_invite_email(repository, user) do
    Emails.repository_invite(repository, user)
    |> Mailer.deliver_now_throttled()
  end
end
