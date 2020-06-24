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
    
    def search() do
        PackageReport.all()
        |> Repo.all()
    end

    def count() do
        PackageReport.count()
        |> Repo.one()
    end

    def get(id) do
        PackageReport.get(id)
        |> Repo.one()
    end

    def change_state(report, comment, state) do
        PackageReport.change_state(report, %{"comment" => comment, "state" => state})
        |> Repo.update()
    end
end