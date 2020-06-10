defmodule Hexpm.Repository.AffectedRelease do
    use Hexpm.Schema

    schema "affected_releases" do
        belongs_to :release, Release
        belongs_to :package_report, PackageReport

        timestamps()
    end

end