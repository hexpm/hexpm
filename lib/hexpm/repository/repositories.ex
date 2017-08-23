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

  # TODO: audit log

  def add_member(repository, username, params) do
    if user = Users.get(username, [:emails]) do
      repository_user = %RepositoryUser{repository_id: repository.id, user_id: user.id}
      changeset = Repository.add_member(repository_user, params)

      case Repo.insert(changeset) do
        {:ok, repository_user} ->
          send_invite_email(repository, user)
          {:ok, repository_user}
        {:error, changeset} ->
          {:error, changeset}
      end
    else
      {:error, :unknown_user}
    end
  end

  def remove_member(repository, username) do
    if user = Users.get(username) do
      count = Repo.aggregate(assoc(repository, :repository_users), :count, :id)

      if count == 1 do
        {:error, :last_member}
      else
        repository_user = Repo.get_by(assoc(repository, :repository_users), user_id: user.id)
        repository_user && Repo.delete!(repository_user)
        :ok
      end
    else
      {:error, :unknown_user}
    end
  end

  def create(name, user) do
    {:ok, result} =
      Multi.new()
      |> Multi.insert(:repository, Repository.changeset(%Repository{name: name}, %{}))
      |> Multi.merge(fn %{repository: repository} ->
        repository_user = %RepositoryUser{repository_id: repository.id, user_id: user.id, role: "admin"}
        Multi.insert(Multi.new(), :repository_user, Repository.add_member(repository_user, %{}))
      end)
      |> Repo.transaction()

    send_invite_email(result.repository, user)
  end

  def change_role(repository, username, params) do
    user = Users.get(username)
    repo_users = Repo.all(assoc(repository, :repository_users))
    repo_user = Enum.find(repo_users, &(&1.user_id == user.id))
    number_admins = Enum.count(repo_users, &(&1.role == "admin"))

    cond do
      !repo_user ->
        {:error, :unknown_user}
      repo_user.role == "admin" and number_admins == 1 ->
        {:error, :last_admin}
      true ->
        repo_user
        |> Repository.change_role(params)
        |> Repo.update()
    end
  end

  defp send_invite_email(repository, user) do
    Emails.repository_invite(repository, user)
    |> Mailer.deliver_now_throttled()
  end
end
