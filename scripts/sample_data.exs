# Run with `mix run sample_data.exs`
# Generates some sample data for development mode

defmodule SampleData do
  def checksum(package) do
    :crypto.hash(:sha256, package) |> Base.encode16
  end

  def create_user(username, email, password) do
    HexWeb.User.create(%{username: username, email: email, password: password}, true)
    |> HexWeb.Repo.insert!
  end

  def last_month do
    {today, _time} = :calendar.universal_time()
    today_days = :calendar.date_to_gregorian_days(today)
    :calendar.gregorian_days_to_date(today_days - 35)
  end
end

alias HexWeb.Package
alias HexWeb.Release
alias HexWeb.Download
alias HexWeb.PackageDownload
alias HexWeb.ReleaseDownload

lorem = "Lorem ipsum dolor sit amet, consectetur adipisicing elit, sed do eiusmod tempor incididunt ut labore et dolore magna aliqua. Ut enim ad minim veniam, quis nostrud exercitation ullamco laboris nisi ut aliquip ex ea commodo consequat. Duis aute irure dolor in reprehenderit in voluptate velit esse cillum dolore eu fugiat nulla pariatur. Excepteur sint occaecat cupidatat non proident, sunt in culpa qui officia deserunt mollit anim id est laborum."

HexWeb.Repo.transaction(fn ->
  eric = SampleData.create_user("eric", "eric@example.com", "eric")
  jose = SampleData.create_user("jose", "jose@example.com", "jose")
  joe = SampleData.create_user("joe", "joe@example.com", "joe")

  if eric == nil or jose == nil or joe == nil do
    IO.puts "\nThere has been an error creating the sample users.\nIf the error says '... already taken' hex_web was probably already set up."
  end

  unless eric == nil do
    {:ok, decimal} =
      Package.create(eric, %{
        "name" => "decimal",
        "meta" => %{
          "maintainers" => ["Eric Meadows-Jönsson"],
          "licenses" => ["Apache 2.0", "MIT"],
          "links" => %{"Github" => "http://example.com/github",
                   "Documentation" => "http://example.com/documentation"},
          "description" => "Arbitrary precision decimal arithmetic for Elixir"}})

    {:ok, _} = Release.create(decimal, %{"version" => "0.0.1", "app" => "decimal", "meta" => %{"app" => "decimal", "build_tools" =>  ["mix"]}}, SampleData.checksum("decimal 0.0.1"))
    {:ok, _} = Release.create(decimal, %{"version" => "0.0.2", "app" => "decimal", "meta" => %{"app" => "decimal", "build_tools" =>  ["mix"]}}, SampleData.checksum("decimal 0.0.2"))
    {:ok, _} = Release.create(decimal, %{"version" => "0.1.0", "app" => "decimal", "meta" => %{"app" => "decimal", "build_tools" =>  ["mix"]}}, SampleData.checksum("decimal 0.1.0"))

    {:ok, postgrex} =
      Package.create(eric, %{
        "name" => "postgrex",
        "meta" => %{
          "maintainers" => ["Eric Meadows-Jönsson", "José Valim"],
          "licenses" => ["Apache 2.0"],
          "links" => %{"Github" => "http://example.com/github"},
          "description" => lorem}})

    {:ok, _} = Release.create(postgrex, %{"version" => "0.0.1", "app" => "postgrex", "meta" => %{"app" => "postgrex", "build_tools" => ["mix"]}}, SampleData.checksum("postgrex 0.0.1"))
    {:ok, _} = Release.create(postgrex, %{"version" => "0.0.2", "app" => "postgrex", "requirements" => %{decimal: "~> 0.0.1"}, "meta" => %{"app" => "postgrex", "build_tools" => ["mix"]}}, SampleData.checksum("postgrex 0.0.2"))
    {:ok, _} = Release.create(postgrex, %{"version" => "0.1.0", "app" => "postgrex", "requirements" => %{decimal: "0.1.0"}, "meta" => %{"app" => "postgrex", "build_tools" => ["mix"]}}, SampleData.checksum("postgrex 0.1.0"))
  end

  unless jose == nil do
    {:ok, ecto} =
      Package.create(jose, %{
        "name" => "ecto",
        "meta" => %{
          "maintainers" => ["Eric Meadows-Jönsson", "José Valim"],
          "licenses" => [],
          "links" => %{"Github" => "http://example.com/github"},
          "description" => lorem}})

    {:ok, _}   = Release.create(ecto, %{"version" => "0.0.1", "app" => "ecto", "meta" => %{"app" => "ecto", "build_tools" => ["mix"]}}, SampleData.checksum("ecto 0.0.1"))
    {:ok, _}   = Release.create(ecto, %{"version" => "0.0.2", "app" => "ecto", "requirements" => %{postgrex: "~> 0.0.1"}, "meta" => %{"app" => "ecto", "build_tools" => ["mix"]}}, SampleData.checksum("ecto 0.0.2"))
    {:ok, _}   = Release.create(ecto, %{"version" => "0.1.0", "app" => "ecto", "requirements" => %{postgrex: "~> 0.0.2"}, "meta" => %{"app" => "ecto", "build_tools" => ["mix"]}}, SampleData.checksum("ecto 0.1.0"))
    {:ok, _}   = Release.create(ecto, %{"version" => "0.1.1", "app" => "ecto", "requirements" => %{postgrex: "~> 0.1.0"}, "meta" => %{"app" => "ecto", "build_tools" => ["mix"]}}, SampleData.checksum("ecto 0.1.1"))
    {:ok, _}   = Release.create(ecto, %{"version" => "0.1.2", "app" => "ecto", "requirements" => %{postgrex: "== 0.1.0", decimal: "0.1.0"}, "meta" => %{"app" => "ecto", "build_tools" => ["mix"]}}, SampleData.checksum("ecto 0.1.2"))
    {:ok, _}   = Release.create(ecto, %{"version" => "0.1.3", "app" => "ecto", "requirements" => %{postgrex: "0.1.0", decimal: "0.1.0"}, "meta" => %{"app" => "ecto", "build_tools" => ["mix"]}}, SampleData.checksum("ecto 0.1.3"))
    {:ok, rel} = Release.create(ecto, %{"version" => "0.2.0", "app" => "ecto", "requirements" => %{postgrex: "~> 0.1.0", decimal: "~> 0.1.0"}, "meta" => %{"app" => "ecto", "build_tools" => ["mix"]}}, SampleData.checksum("ecto 0.2.0"))

    {:ok, yesterday} = Ecto.Type.load(Ecto.Date, HexWeb.Utils.yesterday)
    %Download{release_id: rel.id, downloads: 42, day: yesterday}
    |> HexWeb.Repo.insert!
  end

  unless joe == nil do
    Enum.each(1..100, fn(index) ->
      {:ok, ups} =
      Package.create(joe, %{
        "name" => "ups_" <> to_string(index),
        "meta" => %{
          "maintainers" => ["Joe Somebody"],
          "licenses" => [],
          "links" => %{"Github" => "http://example.com/github"},
          "description" => lorem}})

      {:ok, rel1}   = Release.create(ups, %{"version" => "0.0.1", "app" => "ups", "meta" => %{"app" => "ups", "build_tools" => ["mix"]}}, SampleData.checksum("ups 0.0.1"))
      {:ok, rel2} = Release.create(ups, %{"version" => "0.2.0", "app" => "ups", "requirements" => %{postgrex: "~> 0.1.0", decimal: "~> 0.1.0"}, "meta" => %{"app" => "ups", "build_tools" => ["mix"]}}, SampleData.checksum("ups 0.2.0"))

      {:ok, last_month} = Ecto.Type.load(Ecto.Date, SampleData.last_month)
      %Download{release_id: rel1.id, downloads: div(index, 2), day: last_month}
      |> HexWeb.Repo.insert!

      {:ok, yesterday} = Ecto.Type.load(Ecto.Date, HexWeb.Utils.yesterday)
      %Download{release_id: rel2.id, downloads: div(index, 2) + rem(index, 2), day: yesterday}
      |> HexWeb.Repo.insert!
    end)
  end

  PackageDownload.refresh
  ReleaseDownload.refresh
end)
