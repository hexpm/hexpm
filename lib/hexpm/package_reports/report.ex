defmodule Hexpm.PackageReports.Report do
  use Hexpm.Schema

  schema "package_reports" do
    field :reason, Ecto.Enum, values: ~w(vulnerability malware spam copyright_infringement other)a

    field :summary, :string, redact: true
    field :description, :string, redact: true
    field :status, :string, default: "pending"
    field :external_id, :string
    field :external_url, :string
    field :external_sign_in_url, :string

    field :confirms_criteria, :boolean, default: false, virtual: true
    field :confirms_in_scope, :boolean, default: false, virtual: true

    belongs_to :package, Hexpm.Repository.Package
    belongs_to :reporter, Hexpm.Accounts.User

    timestamps()
  end

  @fields ~w(reason summary description confirms_criteria confirms_in_scope)a

  def changeset(report, attrs) do
    report
    |> cast(attrs, @fields)
    |> validate_required([:reason, :summary, :description])
    |> validate_length(:summary, max: 200)
    |> validate_format(:summary, ~r/\A[^\r\n]+\z/, message: "must be one line")
    |> validate_length(:description, max: 100_000)
    |> validate_vulnerability_confirmations()
  end

  def reason_options do
    [
      {"Vulnerability", "vulnerability"},
      {"Malware", "malware"},
      {"Spam", "spam"},
      {"Copyright infringement", "copyright_infringement"},
      {"Other", "other"}
    ]
  end

  def reason_label(reason) do
    reason = if is_atom(reason), do: Atom.to_string(reason), else: reason

    reason_options()
    |> Enum.find_value(fn {label, value} -> value == reason && label end)
  end

  defp validate_vulnerability_confirmations(changeset) do
    if get_field(changeset, :reason) == :vulnerability do
      changeset
      |> validate_acceptance(:confirms_criteria, message: "must be confirmed")
      |> validate_acceptance(:confirms_in_scope, message: "must be confirmed")
    else
      changeset
    end
  end
end
