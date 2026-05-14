defmodule Hexpm.Factory.ReleaseWithTarballStrategy do
  use ExMachina.Strategy, function_name: :insert_with_tarball

  def handle_insert_with_tarball(%Hexpm.Repository.Release{} = release, %{repo: repo}) do
    package = release.package
    version = to_string(release.version)
    build_tools = release.meta.build_tools

    %{tarball: tarball, inner_checksum: inner, outer_checksum: outer} =
      create_tarball(package.name, version, build_tools)

    release =
      %{release | inner_checksum: inner, outer_checksum: outer}
      |> ExMachina.EctoStrategy.handle_insert(%{repo: repo})
      |> repo.preload(package: :repository)

    store_key = Hexpm.Repository.Assets.tarball_store_key(release)
    Hexpm.Store.put(:repo_bucket, store_key, tarball, [])

    release
  end

  defp create_tarball(name, version, build_tools) do
    metadata = %{
      "name" => name,
      "version" => version,
      "description" => "Fake package #{name}",
      "licenses" => ["Apache-2.0"],
      "files" => ["mix.exs"],
      "requirements" => %{},
      "app" => name,
      "build_tools" => build_tools
    }

    mix_exs = """
    defmodule #{Macro.camelize(name)}.MixProject do
      use Mix.Project

      def project do
        [app: :#{name}, version: "#{version}"]
      end
    end
    """

    {:ok, result} = :hex_tarball.create(metadata, [{~c"mix.exs", mix_exs}])
    result
  end
end
