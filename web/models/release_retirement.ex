defmodule HexWeb.ReleaseRetirement do
  use HexWeb.Web, :model

  embedded_schema do
    field :status, :string
    field :message, :string
  end

  @statuses ~w(other invalid security deprecated renamed)

  def changeset(meta, params) do
    cast(meta, params, ~w(status message))
    |> validate_required(~w(status)a)
    |> validate_inclusion(:status, @statuses)
    |> validate_length(:message, min: 3, max: 140)
  end

  def status_text("other"), do: nil
  def status_text("invalid"), do: "Release invalid"
  def status_text("security"), do: "Security issue"
  def status_text("deprecated"), do: "Deprecated"
  def status_text("renamed"), do: "Renamed"
end
