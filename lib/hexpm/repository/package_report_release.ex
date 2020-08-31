defmodule Hexpm.Repository.PackageReportRelease do
  use Hexpm.Schema

  schema "package_report_releases" do
    belongs_to :release, Release
    belongs_to :package_report, PackageReport

    timestamps()
  end
end
