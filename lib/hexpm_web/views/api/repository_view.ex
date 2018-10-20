defmodule HexpmWeb.API.RepositoryView do
  use HexpmWeb, :view

  def render("index." <> _, %{organizations: organizations}),
    do: render_many(organizations, __MODULE__, "show", as: :organization)

  def render("show." <> _, %{organization: organization}),
    do: render_one(organization, __MODULE__, "show", as: :organization)

  def render("show", %{organization: organization}) do
    # TODO: Add url

    Map.take(organization, [
      :name,
      :public,
      :active,
      :billing_active,
      :inserted_at,
      :updated_at
    ])
  end
end
