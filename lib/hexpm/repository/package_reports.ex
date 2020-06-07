defmodule Hexpm.Repository.PackageReports do
    use Hexpm.Context

    def search(count) do
        PackageReport.all(count)
    end

    def count() do
        Repo.one!(PackageReport.count())
    end
end