defmodule Hexpm.Repository.ReleaseRetirement do
  use Hexpm.Schema

  @derive {HexpmWeb.Stale, last_modified: nil}

  embedded_schema do
    field :reason, :string
    field :message, :string
  end

  @reasons ~w(other invalid security deprecated renamed)

  def changeset(meta, params) do
    cast(meta, params, ~w(reason message)a)
    |> validate_required(~w(reason)a)
    |> validate_length(:message, min: 3, max: 140)
    |> validate_inclusion(:reason, @reasons)
  end

  def reason_text("other"), do: nil
  def reason_text("invalid"), do: "Release invalid"
  def reason_text("security"), do: "Security issue"
  def reason_text("deprecated"), do: "Deprecated"
  def reason_text("renamed"), do: "Renamed"
end
