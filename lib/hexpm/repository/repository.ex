defmodule Hexpm.Repository.Repository do
  use Hexpm.Web, :schema
  @derive {Phoenix.Param, key: :name}

  schema "repositories" do
    field :name, :string
    field :public, :boolean
    timestamps()

    has_many :packages, Package
    has_many :repository_user, RepositoryUser
    has_many :users, through: [:repository_user, :user]
  end

  def has_access(repository, user) do
    from(ro in RepositoryUser,
         where: ro.repository_id == ^repository.id,
         where: ro.user_id == ^user.id,
         select: count(ro.id) >= 1)
  end

  def hexpm() do
    %__MODULE__{
      id: 1,
      name: "hexpm",
      public: true
    }
  end
end
