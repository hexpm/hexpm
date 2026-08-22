defmodule Hexpm.Repository.Policy.OverrideTest do
  use Hexpm.DataCase, async: false

  alias Hexpm.Repository.Policy.Override
  alias Hexpm.Security.Advisory
  alias Hexpm.Security.AdvisoryAffectedVersion

  setup do
    package = insert(:package, name: "safe_package")

    Repo.insert!(%Advisory{
      id: "GHSA-safe-1111-2222",
      summary: "unsafe parsing",
      aliases: ["CVE-2026-1000"],
      published_at: ~U[2026-01-01 00:00:00Z],
      modified_at: ~U[2026-01-01 00:00:00Z]
    })

    Repo.insert!(%AdvisoryAffectedVersion{
      advisory_id: "GHSA-safe-1111-2222",
      package_id: package.id,
      requirement: Version.parse_requirement!("< 2.0.0")
    })

    Repo.insert_all("security_advisory_affected_packages", [
      %{advisory_id: "GHSA-safe-1111-2222", package_id: package.id}
    ])

    %{package: package}
  end

  defp changeset(attrs), do: Override.changeset(%Override{}, attrs, "hexpm")

  test "requires action and package" do
    refute changeset(%{}).valid?
    errors = errors_on(changeset(%{}))
    assert errors.action == "can't be blank"
    assert errors.package == "can't be blank"
  end

  test "validates action inclusion" do
    refute changeset(%{"action" => "maybe", "package" => "phoenix"}).valid?

    for action <- ~w(allow deny cooldown) do
      assert changeset(%{"action" => action, "package" => "phoenix"}).valid?
    end
  end

  test "validates package format" do
    cs = changeset(%{"action" => "allow", "package" => "Bad Name"})
    refute cs.valid?
    assert errors_on(cs).package == "has invalid format"
  end

  test "accepts a valid version requirement" do
    assert changeset(%{"action" => "allow", "package" => "phoenix", "requirement" => "~> 1.7"}).valid?
  end

  test "rejects an invalid version requirement" do
    cs = changeset(%{"action" => "allow", "package" => "phoenix", "requirement" => "nonsense"})
    refute cs.valid?
    assert errors_on(cs).requirement == "is invalid"
  end

  test "blank requirement is nilified" do
    cs = changeset(%{"action" => "allow", "package" => "phoenix", "requirement" => "  "})
    assert cs.valid?
    assert Ecto.Changeset.apply_changes(cs).requirement == nil
  end

  test "accepts a known advisory alias and optional comment" do
    changeset =
      changeset(%{
        "action" => "advisory",
        "package" => "safe_package",
        "requirement" => ">= 1.0.0 and < 2.0.0",
        "advisory_id" => "cve-2026-1000",
        "comment" => "Accepted during migration"
      })

    assert changeset.valid?
  end

  test "accepts a retirement reason and cooldown comment" do
    assert changeset(%{
             "action" => "retirement",
             "package" => "safe_package",
             "retirement_reason" => 2
           }).valid?

    assert changeset(%{
             "action" => "cooldown",
             "package" => "safe_package",
             "comment" => "Upstream release verified"
           }).valid?
  end

  test "requires selector fields to match the action exactly" do
    cases = [
      %{"action" => "advisory", "package" => "safe_package"},
      %{"action" => "retirement", "package" => "safe_package"},
      %{
        "action" => "advisory",
        "package" => "safe_package",
        "advisory_id" => "CVE-2026-1000",
        "retirement_reason" => 2
      },
      %{
        "action" => "allow",
        "package" => "safe_package",
        "advisory_id" => "CVE-2026-1000"
      },
      %{"action" => "cooldown", "package" => "safe_package", "retirement_reason" => 2}
    ]

    for attrs <- cases do
      assert errors_on(changeset(attrs)).action == "does not match its selector fields"
    end
  end

  test "rejects unknown advisories and package mismatches" do
    unknown =
      changeset(%{
        "action" => "advisory",
        "package" => "safe_package",
        "advisory_id" => "CVE-2026-9999"
      })

    mismatch =
      changeset(%{
        "action" => "advisory",
        "package" => "other_package",
        "advisory_id" => "CVE-2026-1000"
      })

    assert errors_on(unknown).advisory_id == "is not an active advisory for this package"
    assert errors_on(mismatch).advisory_id == "is not an active advisory for this package"
  end

  test "validates retirement enums and comments" do
    retirement =
      changeset(%{
        "action" => "retirement",
        "package" => "safe_package",
        "retirement_reason" => 99
      })

    assert errors_on(retirement).retirement_reason == "is invalid"

    for value <- [
          <<255>>,
          "bad\u0000comment",
          "two\nlines",
          "tab\tseparated",
          "line\u2028separator",
          "paragraph\u2029separator",
          "bidi\u202Eoverride"
        ] do
      comment =
        changeset(%{
          "action" => "retirement",
          "package" => "safe_package",
          "retirement_reason" => 2,
          "comment" => value
        })

      assert errors_on(comment).comment ==
               "contains invalid control, format, or separator characters"
    end

    too_long =
      changeset(%{
        "action" => "allow",
        "package" => "safe_package",
        "comment" => String.duplicate("x", 501)
      })

    assert errors_on(too_long).comment == "should be at most 500 character(s)"

    assert changeset(%{
             "action" => "allow",
             "package" => "safe_package",
             "comment" => String.duplicate("e\u0301", 250)
           }).valid?

    too_many_codepoints =
      changeset(%{
        "action" => "allow",
        "package" => "safe_package",
        "comment" => String.duplicate("e\u0301", 251)
      })

    assert errors_on(too_many_codepoints).comment == "should be at most 500 character(s)"
  end

  test "rejects malformed UTF-8 fields without raising" do
    invalid = <<255>>

    cases = [
      {:package, %{"action" => "retirement", "package" => invalid, "retirement_reason" => 2}},
      {:requirement,
       %{
         "action" => "retirement",
         "package" => "safe_package",
         "requirement" => invalid,
         "retirement_reason" => 2
       }},
      {:advisory_id,
       %{"action" => "advisory", "package" => "safe_package", "advisory_id" => invalid}},
      {:comment,
       %{
         "action" => "retirement",
         "package" => "safe_package",
         "comment" => invalid,
         "retirement_reason" => 2
       }}
    ]

    for {field, attrs} <- cases do
      assert Map.has_key?(errors_on(changeset(attrs)), field)
    end
  end
end
