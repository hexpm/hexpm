defmodule Hexpm.Repository.ReleaseRetirement do
  use Hexpm.Schema

  @derive HexpmWeb.Stale

  embedded_schema do
    field :reason, :string
    field :message, :string
  end

  @public_reasons ~w(other invalid security deprecated renamed)
  @private_reasons @public_reasons ++ ~w(report)

  def changeset(meta, params, opts) do
    cast(meta, params, ~w(reason message)a)
    |> validate_required(~w(reason)a)
    |> validate_length(:message, min: 3, max: 140)
    |> validate_reason(Keyword.fetch!(opts, :public))
  end

  defp validate_reason(changeset, true = _public?),
    do: validate_inclusion(changeset, :reason, @public_reasons)

  defp validate_reason(changeset, false = _public?),
    do: validate_inclusion(changeset, :reason, @private_reasons)

  def reason_text("other"), do: nil
  def reason_text("invalid"), do: "Release invalid"
  def reason_text("security"), do: "Security issue"
  def reason_text("deprecated"), do: "Deprecated"
  def reason_text("renamed"), do: "Renamed"
  def reason_text("report"), do: "Reported vulnerability"
end
