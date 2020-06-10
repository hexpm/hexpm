defmodule Hexpm.Repository.PackageReports do
    use Hexpm.Context

    def add(params) do
        Repo.insert(
            PackageReport.build(
                params["releases"],
                params["user"],
                params["package"],
                params
            )
        )
    end
    
    def search(count) do
        PackageReport.all(count)
        |> Repo.all()
    end

    def count() do
        PackageReport.count()
        |> Repo.one()
    end
end