defmodule Hexpm.VersionSortKeyTest do
  use Hexpm.DataCase, async: true

  @identifier_characters Enum.to_list(?0..?9) ++
                           Enum.to_list(?A..?Z) ++ Enum.to_list(?a..?z) ++ [?-]

  test "sort keys follow SemVer precedence" do
    versions =
      ~w(
        1.0.0-1
        1.0.0-alpha
        1.0.0-alpha.1
        1.0.0-alpha.beta
        1.0.0-beta
        1.0.0-beta.2
        1.0.0-beta.11
        1.0.0-rc.1
        1.0.0
        2.0.0
        10.0.0
      )
      |> Enum.map(&Version.parse!/1)

    assert Enum.sort_by(versions, &Hexpm.Version.sort_key/1) == versions
  end

  test "accepts values at the sort key limits" do
    prerelease = "99999999999999." <> String.duplicate("a", 49)
    assert byte_size(prerelease) == 64

    version =
      Version.parse!(
        "99999999999999.99999999999999.99999999999999-" <>
          prerelease
      )

    assert :ok = Hexpm.Version.validate(version)

    assert %{rows: [[key]]} =
             Repo.query!("SELECT public.hexpm_semver_sort_key($1)", [to_string(version)])

    assert key == Hexpm.Version.sort_key(version)
  end

  test "rejects numeric components above the configured limit" do
    versions = [
      {%Version{major: 100_000_000_000_000, minor: 0, patch: 0}, "100000000000000.0.0"},
      {%Version{major: 1, minor: 0, patch: 0, pre: [100_000_000_000_000]},
       "1.0.0-100000000000000"}
    ]

    for {parsed, version} <- versions do
      message = "numeric components must be at most 99999999999999"

      assert {:error, ^message} = Hexpm.Version.validate(parsed)
      assert_sql_error(version, "SemVer numeric components must be at most 99999999999999")
    end
  end

  test "rejects prereleases longer than 64 characters" do
    message = "prerelease must be at most 64 characters"

    for prerelease <- [
          String.duplicate("a", 65),
          Enum.join(List.duplicate("a", 33), ".")
        ] do
      version = "1.0.0-" <> prerelease
      parsed = Version.parse!(version)

      assert {:error, ^message} = Hexpm.Version.validate(parsed)
      assert_sql_error(version, "SemVer prerelease must be at most 64 characters")
    end
  end

  test "stores release sort fields in generated columns" do
    assert %{rows: [["semver_sort_key", "s"], ["semver_stable", "s"]]} =
             Repo.query!("""
             SELECT attname, attgenerated
             FROM pg_catalog.pg_attribute
             WHERE attrelid = 'releases'::regclass
               AND attname IN ('semver_sort_key', 'semver_stable')
             ORDER BY attname
             """)
  end

  property "sort key comparison matches Version.compare/2" do
    check all(left <- version(), right <- version()) do
      assert compare_keys(Hexpm.Version.sort_key(left), Hexpm.Version.sort_key(right)) ==
               Version.compare(left, right)
    end
  end

  property "PostgreSQL and Elixir produce the same sort key" do
    check all(version <- version()) do
      assert %{rows: [[key]]} =
               Repo.query!("SELECT public.hexpm_semver_sort_key($1)", [to_string(version)])

      assert key == Hexpm.Version.sort_key(version)
    end
  end

  property "PostgreSQL orders generated versions by SemVer precedence" do
    check all(versions <- list_of(version(), min_length: 1, max_length: 30)) do
      strings = Enum.map(versions, &to_string/1)

      assert %{rows: rows} =
               Repo.query!(
                 """
                 SELECT version
                 FROM unnest($1::text[]) AS versions(version)
                 ORDER BY public.hexpm_semver_sort_key(version)
                 """,
                 [strings]
               )

      expected = Enum.sort(versions, &(Version.compare(&1, &2) != :gt))
      assert List.flatten(rows) == Enum.map(expected, &to_string/1)
    end
  end

  test "PostgreSQL ignores build metadata for precedence and stability" do
    for {left, right} <- [
          {"1.0.0+abc", "1.0.0+xyz"},
          {"1.0.0-alpha+abc", "1.0.0-alpha+xyz"}
        ] do
      assert Version.compare(Version.parse!(left), Version.parse!(right)) == :eq

      assert %{rows: [[left_key, right_key]]} =
               Repo.query!(
                 "SELECT public.hexpm_semver_sort_key($1), public.hexpm_semver_sort_key($2)",
                 [
                   left,
                   right
                 ]
               )

      assert left_key == right_key
    end

    package = insert(:package)

    assert %{rows: [[key, true]]} =
             Repo.query!(
               """
               INSERT INTO releases
                 (package_id, version, inner_checksum, has_docs, meta, inserted_at, updated_at)
               VALUES ($1, $2, $3, false, '{}'::jsonb, now(), now())
               RETURNING semver_sort_key, semver_stable
               """,
               [package.id, "1.0.0+abc-def", <<0::256>>]
             )

    assert key == Hexpm.Version.sort_key(Version.parse!("1.0.0+abc-def"))
  end

  defp version do
    gen all(
          major <- integer(0..99_999_999_999_999),
          minor <- integer(0..99_999_999_999_999),
          patch <- integer(0..99_999_999_999_999),
          pre <- prerelease(),
          build <- build_metadata()
        ) do
      %Version{major: major, minor: minor, patch: patch, pre: pre, build: build}
    end
  end

  defp prerelease do
    one_of([
      constant([]),
      list_of(one_of([integer(0..99_999_999_999_999), alphanumeric_identifier()]),
        min_length: 1,
        max_length: 4
      )
      |> filter(fn identifiers ->
        identifiers
        |> Enum.map_join(".", &to_string/1)
        |> byte_size()
        |> Kernel.<=(64)
      end)
    ])
  end

  defp alphanumeric_identifier do
    identifier()
    |> filter(&String.match?(&1, ~r/[A-Za-z-]/))
  end

  defp build_metadata do
    one_of([
      constant(nil),
      identifier()
      |> list_of(min_length: 1, max_length: 4)
      |> map(&Enum.join(&1, "."))
    ])
  end

  defp identifier do
    @identifier_characters
    |> member_of()
    |> list_of(min_length: 1, max_length: 12)
    |> map(&List.to_string/1)
  end

  defp compare_keys(left, right) when left < right, do: :lt
  defp compare_keys(left, right) when left > right, do: :gt
  defp compare_keys(_left, _right), do: :eq

  defp assert_sql_error(version, message) do
    assert {:error, %Postgrex.Error{postgres: %{message: ^message}}} =
             Repo.transaction(
               fn ->
                 case Repo.query("SELECT public.hexpm_semver_sort_key($1)", [version]) do
                   {:error, error} -> Repo.rollback(error)
                   {:ok, _result} -> flunk("expected PostgreSQL to reject #{version}")
                 end
               end,
               mode: :savepoint
             )
  end
end
