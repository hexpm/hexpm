defmodule Hexpm.Repository.Repository do
  use Hexpm.Schema

  @derive HexpmWeb.Stale
  @derive {Phoenix.Param, key: :name}

  schema "repositories" do
    field :name, :string
    field :public, :boolean, default: false
    timestamps()

    belongs_to :organization, Organization
    has_many :packages, Package
  end

  def hexpm(opts \\ []) do
    organization =
      if Keyword.get(opts, :recursive, true) do
        Organization.hexpm(recursive: false)
      else
        %Ecto.Association.NotLoaded{}
      end

    %__MODULE__{
      id: 1,
      name: "hexpm",
      public: true,
      organization: organization,
      organization_id: 1
    }
  end
end
