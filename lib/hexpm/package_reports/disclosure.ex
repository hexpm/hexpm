defmodule Hexpm.PackageReports.Disclosure do
  @moduledoc """
  A user whose name, username and primary email address hex.pm has sent to the
  CNA, through a vulnerability report or a contact lookup. When the user deletes
  their account the CNA is told, as GDPR Article 19 requires for the recipients
  of erased data.
  """

  use Hexpm.Schema

  schema "varsel_disclosures" do
    belongs_to :user, User

    timestamps(updated_at: false)
  end
end
