defmodule SampleData do
  def checksum(package) do
    :crypto.hash(:sha256, package) |> Base.encode16
  end

  def create_user(username, email, password) do
    HexWeb.User.build(%{username: username, emails: [%{email: email}], password: password}, true)
    |> HexWeb.Repo.insert!
  end

  def last_month do
    {today, _time} = :calendar.universal_time()

    today
    |> :calendar.date_to_gregorian_days()
    |> Kernel.-(35)
    |> :calendar.gregorian_days_to_date()
    |> Date.from_erl!()
  end
end

alias HexWeb.Package
alias HexWeb.Release
alias HexWeb.Download
alias HexWeb.PackageDownload
alias HexWeb.ReleaseDownload

lorem = "Lorem ipsum dolor sit amet, consectetur adipisicing elit, sed do eiusmod tempor incididunt ut labore et dolore magna aliqua. Ut enim ad minim veniam, quis nostrud exercitation ullamco laboris nisi ut aliquip ex ea commodo consequat. Duis aute irure dolor in reprehenderit in voluptate velit esse cillum dolore eu fugiat nulla pariatur. Excepteur sint occaecat cupidatat non proident, sunt in culpa qui officia deserunt mollit anim id est laborum."

HexWeb.Repo.transaction(fn ->
  eric = SampleData.create_user("eric", "eric@example.com", "ericric")
  jose = SampleData.create_user("jose", "jose@example.com", "josejose")
  joe = SampleData.create_user("joe", "joe@example.com", "joejoejoe")
  justin = SampleData.create_user("justin", "justin@example.com", "justinjustin")

  if eric == nil or jose == nil or joe == nil or justin == nil do
    IO.puts "\nThere has been an error creating the sample users.\nIf the error says '... already taken' hex_web was probably already set up."
  end

  unless eric == nil do
    decimal =
      Package.build(eric, %{
        "name" => "decimal",
        "meta" => %{
          "maintainers" => ["Eric Meadows-Jönsson"],
          "licenses" => ["Apache 2.0", "MIT"],
          "links" => %{"Github" => "http://example.com/github",
                   "Documentation" => "http://example.com/documentation"},
          "description" => "Arbitrary precision decimal arithmetic for Elixir"}})
      |> HexWeb.Repo.insert!

    Release.build(decimal, %{"version" => "0.0.1", "app" => "decimal", "meta" => %{"app" => "decimal", "build_tools" =>  ["mix"]}}, SampleData.checksum("decimal 0.0.1")) |> HexWeb.Repo.insert!
    Release.build(decimal, %{"version" => "0.0.2", "app" => "decimal", "meta" => %{"app" => "decimal", "build_tools" =>  ["mix"]}}, SampleData.checksum("decimal 0.0.2")) |> HexWeb.Repo.insert!
    Release.build(decimal, %{"version" => "0.1.0", "app" => "decimal", "meta" => %{"app" => "decimal", "build_tools" =>  ["mix"]}}, SampleData.checksum("decimal 0.1.0")) |> HexWeb.Repo.insert!

    postgrex =
      Package.build(eric, %{
        "name" => "postgrex",
        "meta" => %{
          "maintainers" => ["Eric Meadows-Jönsson", "José Valim"],
          "licenses" => ["Apache 2.0"],
          "links" => %{"Github" => "http://example.com/github"},
          "description" => lorem}})
      |> HexWeb.Repo.insert!

    Release.build(postgrex, %{"version" => "0.0.1", "app" => "postgrex", "meta" => %{"app" => "postgrex", "build_tools" => ["mix"]}}, SampleData.checksum("postgrex 0.0.1")) |> HexWeb.Repo.insert!
    reqs = [%{"name" => "decimal", "app" => "decimal", "requirement" => "~> 0.0.1", "optional" => false}]
    Release.build(postgrex, %{"version" => "0.0.2", "app" => "postgrex", "requirements" => reqs, "meta" => %{"app" => "postgrex", "build_tools" => ["mix"]}}, SampleData.checksum("postgrex 0.0.2")) |> HexWeb.Repo.insert!
    reqs = [%{"name" => "decimal", "app" => "decimal", "requirement" => "0.1.0", "optional" => false}]
    Release.build(postgrex, %{"version" => "0.1.0", "app" => "postgrex", "requirements" => reqs, "meta" => %{"app" => "postgrex", "build_tools" => ["mix"]}}, SampleData.checksum("postgrex 0.1.0")) |> HexWeb.Repo.insert!
  end

  unless jose == nil do
    ecto =
      Package.build(jose, %{
        "name" => "ecto",
        "meta" => %{
          "maintainers" => ["Eric Meadows-Jönsson", "José Valim"],
          "licenses" => [],
          "links" => %{"Github" => "http://example.com/github"},
          "description" => lorem}})
      |> HexWeb.Repo.insert!

    Release.build(ecto, %{"version" => "0.0.1", "app" => "ecto", "meta" => %{"app" => "ecto", "build_tools" => ["mix"]}}, SampleData.checksum("ecto 0.0.1")) |> HexWeb.Repo.insert!
    reqs = [%{"name" => "postgrex", "app" => "postgrex", "requirement" => "~> 0.0.1", "optional" => false}]
    Release.build(ecto, %{"version" => "0.0.2", "app" => "ecto", "requirements" => reqs, "meta" => %{"app" => "ecto", "build_tools" => ["mix"]}}, SampleData.checksum("ecto 0.0.2")) |> HexWeb.Repo.insert!
    reqs = [%{"name" => "postgrex", "app" => "postgrex", "requirement" => "~> 0.0.2", "optional" => false}]
    Release.build(ecto, %{"version" => "0.1.0", "app" => "ecto", "requirements" => reqs, "meta" => %{"app" => "ecto", "build_tools" => ["mix"]}}, SampleData.checksum("ecto 0.1.0")) |> HexWeb.Repo.insert!
    reqs = [%{"name" => "postgrex", "app" => "postgrex", "requirement" => "~> 0.1.0", "optional" => false}]
    Release.build(ecto, %{"version" => "0.1.1", "app" => "ecto", "requirements" => reqs, "meta" => %{"app" => "ecto", "build_tools" => ["mix"]}}, SampleData.checksum("ecto 0.1.1")) |> HexWeb.Repo.insert!
    reqs = [%{"name" => "postgrex", "app" => "postgrex", "requirement" => "== 0.1.0", "optional" => false}, %{"name" => "decimal", "app" => "decimal", "requirement" => "0.1.0", "optional" => false}]
    Release.build(ecto, %{"version" => "0.1.2", "app" => "ecto", "requirements" => reqs, "meta" => %{"app" => "ecto", "build_tools" => ["mix"]}}, SampleData.checksum("ecto 0.1.2")) |> HexWeb.Repo.insert!
    reqs = [%{"name" => "postgrex", "app" => "postgrex", "requirement" => "0.1.0", "optional" => false}, %{"name" => "decimal", "app" => "decimal", "requirement" => "0.1.0", "optional" => false}]
    Release.build(ecto, %{"version" => "0.1.3", "app" => "ecto", "requirements" => reqs, "meta" => %{"app" => "ecto", "build_tools" => ["mix"]}}, SampleData.checksum("ecto 0.1.3")) |> HexWeb.Repo.insert!
    reqs = [%{"name" => "postgrex", "app" => "postgrex", "requirement" => "~> 0.1.0", "optional" => false}, %{"name" => "decimal", "app" => "decimal", "requirement" => "~> 0.1.0", "optional" => false}]
    rel = Release.build(ecto, %{"version" => "0.2.0", "app" => "ecto", "requirements" => reqs, "meta" => %{"app" => "ecto", "build_tools" => ["mix"]}}, SampleData.checksum("ecto 0.2.0")) |> HexWeb.Repo.insert!

    %Download{release_id: rel.id, downloads: 42, day: HexWeb.Utils.utc_yesterday}
    |> HexWeb.Repo.insert!
  end

  unless joe == nil do
    Enum.each(1..100, fn(index) ->
      ups =
        Package.build(joe, %{
          "name" => "ups_" <> to_string(index),
          "meta" => %{
            "maintainers" => ["Joe Somebody"],
            "licenses" => [],
            "links" => %{"Github" => "http://example.com/github"},
            "description" => lorem}})
        |> HexWeb.Repo.insert!

      rel1 = Release.build(ups, %{"version" => "0.0.1", "app" => "ups", "meta" => %{"app" => "ups", "build_tools" => ["mix"]}}, SampleData.checksum("ups 0.0.1")) |> HexWeb.Repo.insert!
      reqs = [%{"name" => "postgrex", "app" => "postgrex", "requirement" => "~> 0.1.0", "optional" => false}, %{"name" => "decimal", "app" => "postgrex", "requirement" => "~> 0.1.0", "optional" => false}]
      rel2 = Release.build(ups, %{"version" => "0.2.0", "app" => "ups", "requirements" => reqs, "meta" => %{"app" => "ups", "build_tools" => ["mix"]}}, SampleData.checksum("ups 0.2.0")) |> HexWeb.Repo.insert!

      %Download{release_id: rel1.id, downloads: div(index, 2), day: SampleData.last_month}
      |> HexWeb.Repo.insert!

      %Download{release_id: rel2.id, downloads: div(index, 2) + rem(index, 2), day: HexWeb.Utils.utc_yesterday}
      |> HexWeb.Repo.insert!
    end)
  end

  unless justin == nil do
    nerves =
      Package.build(justin, %{
        "name" => "nerves",
        "meta" => %{
          "maintainers" => ["Justin Schneck", "Frank Hunleth"],
          "licenses" => ["Apache 2.0"],
          "links" => %{"Github" => "http://example.com/github"},
          "description" => lorem,
          "extra" => %{
            "foo" => %{"bar" => "baz"},
            "key" => "value 1"}}})
      |> HexWeb.Repo.insert!

    rel = Release.build(nerves, %{"version" => "0.0.1", "app" => "nerves", "meta" => %{"app" => "nerves", "build_tools" => ["mix"]}}, SampleData.checksum("nerves 0.0.1")) |> HexWeb.Repo.insert!

    %Download{release_id: rel.id, downloads: 20, day: HexWeb.Utils.utc_yesterday}
    |> HexWeb.Repo.insert!

    Enum.each(1..10, fn(index) ->
      nerves_pkg =
        Package.build(justin, %{
          "name" => "nerves_pkg_#{index}",
          "meta" => %{
            "maintainers" => ["Justin Schneck", "Frank Hunleth"],
            "licenses" => ["Apache 2.0"],
            "links" => %{"Github" => "http://example.com/github"},
            "description" => lorem,
            "extra" => %{
              "list" => ["a", "b", "c"],
              "foo" => %{"bar" => "baz"},
              "key" => "value"}}})
        |> HexWeb.Repo.insert!

      rel = Release.build(nerves_pkg, %{"version" => "0.0.1", "app" => "nerves_pkg_#{index}", "meta" => %{"app" => "nerves_pkg_#{index}", "build_tools" => ["mix"]}}, SampleData.checksum("nerves_pkg_#{index} 0.0.1")) |> HexWeb.Repo.insert!

      %Download{release_id: rel.id, downloads: div(index, 2) + rem(index, 2), day: HexWeb.Utils.utc_yesterday}
      |> HexWeb.Repo.insert!
    end)
  end

  HexWeb.Repo.refresh_view(PackageDownload)
  HexWeb.Repo.refresh_view(ReleaseDownload)
end)
