defmodule HexpmWeb.PackageOwnerLive.AddOwnerTest do
  use HexpmWeb.ConnCase

  import Phoenix.LiveViewTest

  alias Hexpm.WorkloadIdentities.TrustedRepository
  alias HexpmWeb.PackageOwnerLive.AddOwner

  setup do
    Ecto.Adapters.SQL.Sandbox.mode(Hexpm.RepoBase, {:shared, self()})

    current_user = insert(:user)
    package = insert(:package, package_owners: [build(:package_owner, user: current_user)])
    package = Hexpm.Repo.preload(package, :repository)
    session = %{"package_id" => package.id}

    %{
      conn: test_login(build_conn(), current_user),
      session: session,
      package: package,
      current_user: current_user
    }
  end

  test "renders the Add owner trigger button", %{conn: conn, session: session} do
    {:ok, _view, html} = live_isolated(conn, AddOwner, session: session)
    assert html =~ "Add owner"
    assert html =~ ~s(id="add-owner-modal")
  end

  test "starts with empty preview", %{conn: conn, session: session} do
    {:ok, _view, html} = live_isolated(conn, AddOwner, session: session)
    assert html =~ "Enter a Hex username to preview the user"
  end

  test "shows user preview when a matching user is found", %{conn: conn, session: session} do
    target = insert(:user, username: "preview_target", full_name: "Preview Target")

    {:ok, view, _html} = live_isolated(conn, AddOwner, session: session)

    html =
      view
      |> form("#add-owner-form", username: target.username, level: "maintainer")
      |> render_change()

    assert html =~ "preview_target"
    assert html =~ "Preview Target"
    refute html =~ "Enter a Hex username"
    refute html =~ "No user found"

    assert html =~ ~s(href="/users/preview_target")
  end

  test "shows not-found state for unknown usernames", %{conn: conn, session: session} do
    {:ok, view, _html} = live_isolated(conn, AddOwner, session: session)

    html =
      view
      |> form("#add-owner-form", username: "no_such_user", level: "maintainer")
      |> render_change()

    assert html =~ "No user found"
    assert html =~ "no_such_user"
  end

  test "submit button is disabled until a user is found", %{conn: conn, session: session} do
    insert(:user, username: "findable_user")

    {:ok, view, html} = live_isolated(conn, AddOwner, session: session)
    assert submit_button_disabled?(html)

    after_lookup =
      view
      |> form("#add-owner-form", username: "findable_user", level: "maintainer")
      |> render_change()

    refute submit_button_disabled?(after_lookup)
  end

  test "refuses a user whose primary email is unverified", %{conn: conn, session: session} do
    insert(:user,
      username: "unverified_user",
      full_name: "Unverified Person",
      emails: [build(:email, verified: false)]
    )

    {:ok, view, _html} = live_isolated(conn, AddOwner, session: session)

    html =
      view
      |> form("#add-owner-form", username: "unverified_user", level: "maintainer")
      |> render_change()

    assert html =~ "unverified_user"
    assert html =~ "has not verified their primary email"
    refute html =~ "Unverified Person"
    refute html =~ ~s(href="/users/unverified_user")
    assert submit_button_disabled?(html)
  end

  describe "an organization" do
    setup %{current_user: current_user} do
      maintainer = insert(:user, username: "transfer_maintainer")
      owning_organization = insert(:organization)

      package =
        insert(:package,
          package_owners: [
            build(:package_owner, user: current_user, level: "full"),
            build(:package_owner, user: maintainer, level: "maintainer"),
            build(:package_owner, user: owning_organization.user, level: "full")
          ]
        )

      insert(:workload_identity,
        package: package,
        repositories: [%TrustedRepository{name: "acme/package-identity", id: "22"}],
        workflow: "release.yml"
      )

      insert(:organization_workload_identity,
        organization: owning_organization,
        role: "write",
        repositories: [%TrustedRepository{name: "acme/owning-identity", id: "33"}],
        workflow: "publish.yml",
        covers_public: true
      )

      organization = insert(:organization)

      insert(:organization_workload_identity,
        organization: organization,
        role: "write",
        repositories: [%TrustedRepository{name: "acme/target-identity", id: "44"}],
        workflow: "target.yml",
        covers_public: true
      )

      %{
        session: %{"package_id" => package.id},
        package: package,
        maintainer: maintainer,
        owning_organization: owning_organization,
        organization: organization
      }
    end

    test "is added by a transfer that lists what it removes", %{
      conn: conn,
      session: session,
      package: package,
      current_user: current_user,
      maintainer: maintainer,
      owning_organization: owning_organization,
      organization: organization
    } do
      {:ok, view, _html} = live_isolated(conn, AddOwner, session: session)

      html =
        view
        |> form("#add-owner-form", username: organization.name, level: "maintainer")
        |> render_change()

      document = LazyHTML.from_fragment(html)

      assert document
             |> LazyHTML.query(~s(input[type="hidden"][name="transfer_to"]))
             |> LazyHTML.attribute("value") == [organization.name]

      assert document |> LazyHTML.query("#add-owner-level[disabled]") |> Enum.count() == 1

      assert document
             |> LazyHTML.query("#add-owner-transfer-checkbox[checked][disabled]")
             |> Enum.count() == 1

      assert document
             |> LazyHTML.query("#add-owner-level option[selected]")
             |> LazyHTML.attribute("value") == ["full"]

      assert document |> LazyHTML.query(~s(button[type="submit"])) |> text() ==
               "Transfer to #{organization.name}"

      assert document
             |> LazyHTML.query("#add-owner-form")
             |> LazyHTML.attribute("phx-submit") == ["confirm_transfer"]

      refute submit_button_disabled?(html)

      assert document |> LazyHTML.query("#add-owner-transfer-irreversible") |> text() ==
               "This can't be undone. After the transfer you no longer have any " <>
                 "ownership access to #{package.name}."

      warning = document |> LazyHTML.query("#add-owner-transfer") |> text()

      assert warning =~
               "Adding an organization transfers the package to it. " <>
                 "#{organization.name} becomes the only owner of #{package.name}."

      assert document |> LazyHTML.query("#add-owner-transfer strong") |> Enum.map(&text/1) ==
               [organization.name, package.name, package.name, package.name]

      assert transfer_items(document) ==
               Enum.sort([
                 "#{current_user.username} (you)",
                 maintainer.username,
                 owning_organization.name,
                 "acme/package-identity (release.yml)",
                 "#{owning_organization.name}: acme/owning-identity (publish.yml)"
               ])

      assert warning =~ "The transfer removes these owners:"

      assert warning =~
               "The transfer removes these workload identities of #{package.name}: " <>
                 "acme/package-identity (release.yml)"

      assert warning =~
               "These organization workload identities stop publishing #{package.name}: " <>
                 "#{owning_organization.name}: acme/owning-identity (publish.yml)"

      refute warning =~ "acme/target-identity"
    end

    test "says a member of the new organization keeps access through it", %{
      conn: conn,
      session: session,
      package: package,
      current_user: current_user,
      organization: organization
    } do
      insert(:organization_user, organization: organization, user: current_user, role: "write")
      {:ok, view, _html} = live_isolated(conn, AddOwner, session: session)

      assert view
             |> form("#add-owner-form", username: organization.name)
             |> render_change()
             |> LazyHTML.from_fragment()
             |> LazyHTML.query("#add-owner-transfer-irreversible")
             |> text() ==
               "This can't be undone. After the transfer you only have access to " <>
                 "#{package.name} through your membership of #{organization.name}."
    end

    test "transferring to yourself only says it can't be undone", %{
      conn: conn,
      session: session,
      current_user: current_user
    } do
      {:ok, view, _html} = live_isolated(conn, AddOwner, session: session)

      assert view
             |> form("#add-owner-form", username: current_user.username, transfer: "true")
             |> render_change()
             |> LazyHTML.from_fragment()
             |> LazyHTML.query("#add-owner-transfer-irreversible")
             |> text() == "This can't be undone."
    end

    test "already owning the package is not listed as removed", %{
      conn: conn,
      session: session,
      owning_organization: owning_organization
    } do
      {:ok, view, _html} = live_isolated(conn, AddOwner, session: session)

      document =
        view
        |> form("#add-owner-form", username: owning_organization.name)
        |> render_change()
        |> LazyHTML.from_fragment()

      assert document |> LazyHTML.query(~s(button[type="submit"])) |> text() ==
               "Transfer to #{owning_organization.name}"

      refute owning_organization.name in transfer_items(document)
      refute document |> LazyHTML.query("#add-owner-transfer") |> text() =~ "acme/owning-identity"
    end

    test "a user is transferred to when Transfer ownership is checked", %{
      conn: conn,
      session: session,
      package: package,
      current_user: current_user,
      owning_organization: owning_organization
    } do
      target = insert(:user)
      {:ok, view, _html} = live_isolated(conn, AddOwner, session: session)

      html =
        view
        |> form("#add-owner-form", username: target.username, transfer: "true")
        |> render_change()

      document = LazyHTML.from_fragment(html)

      assert document
             |> LazyHTML.query(~s(input[type="hidden"][name="transfer_to"]))
             |> LazyHTML.attribute("value") == [target.username]

      assert document |> LazyHTML.query("#add-owner-level[disabled]") |> Enum.count() == 1

      assert document |> LazyHTML.query(~s(button[type="submit"])) |> text() ==
               "Transfer to #{target.username}"

      refute submit_button_disabled?(html)

      warning = document |> LazyHTML.query("#add-owner-transfer") |> text()
      assert warning =~ "#{target.username} becomes the only owner of #{package.name}."
      refute warning =~ "Adding an organization"

      assert transfer_items(document) ==
               Enum.sort([
                 "#{current_user.username} (you)",
                 "transfer_maintainer",
                 owning_organization.name,
                 "acme/package-identity (release.yml)",
                 "#{owning_organization.name}: acme/owning-identity (publish.yml)"
               ])
    end

    test "unchecking Transfer ownership adds the user", %{
      conn: conn,
      session: session
    } do
      target = insert(:user)
      {:ok, view, _html} = live_isolated(conn, AddOwner, session: session)

      view
      |> form("#add-owner-form", username: target.username, transfer: "true")
      |> render_change()

      # An unchecked checkbox isn't in the form data.
      document =
        view
        |> render_change("lookup", %{"username" => target.username, "level" => "maintainer"})
        |> LazyHTML.from_fragment()

      assert document |> LazyHTML.query(~s(input[name="transfer_to"])) |> Enum.empty?()
      assert document |> LazyHTML.query("#add-owner-transfer") |> Enum.empty?()
      assert document |> LazyHTML.query("#add-owner-level[disabled]") |> Enum.empty?()

      assert document
             |> LazyHTML.query("#add-owner-level option[selected]")
             |> LazyHTML.attribute("value") == ["maintainer"]

      assert document |> LazyHTML.query(~s(button[type="submit"])) |> text() == "Add as owner"
      assert document |> LazyHTML.query("#add-owner-form[phx-submit]") |> Enum.empty?()
    end

    test "Transfer to <name> asks for the package name before posting", %{
      conn: conn,
      session: session,
      package: package,
      organization: organization
    } do
      {:ok, view, _html} = live_isolated(conn, AddOwner, session: session)

      view
      |> form("#add-owner-form", username: organization.name)
      |> render_change()

      document =
        view
        |> form("#add-owner-form")
        |> render_submit()
        |> LazyHTML.from_fragment()

      assert document |> LazyHTML.query("#add-owner-modal-title") |> text() ==
               "Transfer #{package.name} to #{organization.name}?"

      assert [input] = document |> LazyHTML.query("#add-owner-confirm-package") |> Enum.to_list()
      assert LazyHTML.attribute(input, "name") == ["package_name"]
      assert LazyHTML.attribute(input, "pattern") == [package.name]
      assert LazyHTML.attribute(input, "required") != []

      assert document
             |> LazyHTML.query(~s(input[type="hidden"][name="transfer_to"]))
             |> LazyHTML.attribute("value") == [organization.name]

      assert document |> LazyHTML.query("#add-owner-transfer") |> Enum.count() == 1
      assert document |> LazyHTML.query("#add-owner-form[phx-submit]") |> Enum.empty?()

      assert document |> LazyHTML.query(~s(button[type="submit"])) |> text() ==
               "Transfer #{package.name}"

      # Typing the package name doesn't leave the confirm step.
      assert render_change(view, "lookup", %{"package_name" => package.name}) =~
               ~s(id="add-owner-confirm-package")
    end

    test "Back leaves the confirm step", %{
      conn: conn,
      session: session,
      organization: organization
    } do
      {:ok, view, _html} = live_isolated(conn, AddOwner, session: session)

      view
      |> form("#add-owner-form", username: organization.name)
      |> render_change()

      view |> form("#add-owner-form") |> render_submit()

      document =
        view
        |> element("button", "Back")
        |> render_click()
        |> LazyHTML.from_fragment()

      assert document |> LazyHTML.query("#add-owner-confirm-package") |> Enum.empty?()
      assert document |> LazyHTML.query("#add-owner-modal-title") |> text() == "Add owner"

      assert document |> LazyHTML.query(~s(button[type="submit"])) |> text() ==
               "Transfer to #{organization.name}"
    end

    test "leaves transfer mode when the username changes to a user", %{
      conn: conn,
      session: session,
      maintainer: maintainer,
      organization: organization
    } do
      {:ok, view, _html} = live_isolated(conn, AddOwner, session: session)

      assert view
             |> form("#add-owner-form", username: organization.name)
             |> render_change() =~ ~s(name="transfer_to")

      document =
        view
        |> form("#add-owner-form", username: maintainer.username)
        |> render_change()
        |> LazyHTML.from_fragment()

      assert document |> LazyHTML.query(~s(input[name="transfer_to"])) |> Enum.empty?()
      assert document |> LazyHTML.query("#add-owner-transfer-checkbox[checked]") |> Enum.empty?()
      assert document |> LazyHTML.query("#add-owner-transfer") |> Enum.empty?()
      assert document |> LazyHTML.query("#add-owner-level[disabled]") |> Enum.empty?()
      assert document |> LazyHTML.query(~s(button[type="submit"])) |> text() == "Add as owner"
    end
  end

  describe "a private package" do
    setup %{current_user: current_user} do
      repository = insert(:repository)

      insert(:organization_user,
        organization: repository.organization,
        user: current_user,
        role: "admin"
      )

      package = insert(:package, repository_id: repository.id)

      %{
        repository: repository,
        package: package,
        session: %{"package_id" => package.id}
      }
    end

    test "can't be transferred", %{
      conn: conn,
      session: session,
      package: package,
      repository: repository
    } do
      {:ok, _view, html} = live_isolated(conn, AddOwner, session: session)
      document = LazyHTML.from_fragment(html)

      assert document |> LazyHTML.query("#add-owner-transfer-checkbox") |> Enum.empty?()

      assert document |> LazyHTML.query("#add-owner-private-note") |> text() ==
               "#{package.name} is part of the #{repository.name} organization, " <>
                 "so it can't be transferred. Only members of #{repository.name} can own it."
    end

    test "refuses an organization", %{
      conn: conn,
      session: session,
      package: package,
      repository: repository
    } do
      organization = insert(:organization)
      {:ok, view, _html} = live_isolated(conn, AddOwner, session: session)

      html =
        view
        |> form("#add-owner-form", username: organization.name, level: "maintainer")
        |> render_change()

      assert html |> LazyHTML.from_fragment() |> LazyHTML.query("#add-owner-modal") |> text() =~
               "is an organization. Only members of #{repository.name} can own #{package.name}."

      refute html =~ ~s(name="transfer_to")
      assert submit_button_disabled?(html)
    end

    test "refuses a user who isn't a member", %{
      conn: conn,
      session: session,
      package: package,
      repository: repository
    } do
      outsider = insert(:user)
      {:ok, view, _html} = live_isolated(conn, AddOwner, session: session)

      html =
        view
        |> form("#add-owner-form", username: outsider.username, level: "maintainer")
        |> render_change()

      assert html |> LazyHTML.from_fragment() |> LazyHTML.query("#add-owner-modal") |> text() =~
               "isn't a member of #{repository.name}. " <>
                 "Only members of #{repository.name} can own #{package.name}."

      assert submit_button_disabled?(html)
    end

    test "adds a member without a transfer", %{
      conn: conn,
      session: session,
      repository: repository
    } do
      member = insert(:user)
      insert(:organization_user, organization: repository.organization, user: member)
      {:ok, view, _html} = live_isolated(conn, AddOwner, session: session)

      html =
        render_change(view, "lookup", %{
          "username" => member.username,
          "level" => "maintainer",
          "transfer" => "true"
        })

      assert html =~ ~s(href="/users/#{member.username}")
      refute html =~ ~s(name="transfer_to")
      refute submit_button_disabled?(html)
    end
  end

  test "shows nothing to someone who doesn't manage the package", %{session: session} do
    {:ok, _view, html} =
      live_isolated(test_login(build_conn(), insert(:user)), AddOwner, session: session)

    assert html =~ "You can no longer change the owners of"
    refute html =~ ~s(id="add-owner-form")
  end

  test "stops looking up once the package is transferred away", %{
    conn: conn,
    session: session,
    package: package,
    current_user: current_user
  } do
    organization = insert(:organization)

    insert(:organization_workload_identity,
      organization: organization,
      role: "write",
      repositories: [%TrustedRepository{name: "acme/new-owner-identity", id: "55"}],
      workflow: "new-owner.yml",
      covers_public: true
    )

    {:ok, view, _html} = live_isolated(conn, AddOwner, session: session)

    {:ok, _owner} =
      package
      |> Hexpm.Repo.preload(repository: :organization)
      |> Hexpm.Repository.Owners.add(
        organization.user,
        %{"transfer" => true, "level" => "full"},
        audit: test_audit_data(current_user)
      )

    html =
      render_change(view, "lookup", %{"username" => current_user.username, "transfer" => "true"})

    assert html =~
             ~s(You can no longer change the owners of <strong class="font-semibold text-grey-900 dark:text-white">#{package.name}</strong>.)

    refute html =~ "acme/new-owner-identity"
    refute html =~ ~s(id="add-owner-form")
  end

  defp transfer_items(document) do
    document
    |> LazyHTML.query("#add-owner-transfer li")
    |> Enum.map(&text/1)
    |> Enum.sort()
  end

  # The separator also lands between a bold name and the punctuation after it.
  defp text(document) do
    document
    |> LazyHTML.text(separator: " ")
    |> String.replace(~r/\s+/, " ")
    |> String.replace(~r/ ([.,:])/, "\\1")
    |> String.trim()
  end

  defp submit_button_disabled?(html) do
    doc = LazyHTML.from_fragment(html)

    doc
    |> LazyHTML.query(~s(button[type="submit"]))
    |> Enum.any?(fn button -> LazyHTML.attribute(button, "disabled") != [] end)
  end
end
