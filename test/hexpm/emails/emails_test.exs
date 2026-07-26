defmodule Hexpm.EmailsTest do
  use Hexpm.DataCase, async: false

  alias Hexpm.Accounts.{Organization, User}
  alias Hexpm.Emails
  alias HexpmWeb.EmailView.Common

  defp package_published_email() do
    Emails.package_published([build(:user)], build(:user), "cowboy", "2.16.1")
  end

  describe "html layout" do
    test "header does not rely on flexbox" do
      refute package_published_email().html_body =~ "display: flex"
    end

    test "header wordmark is a link with explicit white color and no underline" do
      assert [{"a", attrs, _children}] =
               package_published_email().html_body
               |> Floki.parse_document!()
               |> Floki.find("a")
               |> Enum.filter(&(&1 |> Floki.text() |> String.trim() == "Hex"))

      attrs = Map.new(attrs)
      assert attrs["href"] == Application.fetch_env!(:hexpm, :email_base_url) <> "/"
      assert attrs["style"] =~ "color: #ffffff"
      assert attrs["style"] =~ "text-decoration: none"
    end

    test "logo is a png image" do
      assert [src] =
               package_published_email().html_body
               |> Floki.parse_document!()
               |> Floki.attribute("img", "src")

      assert src =~ "hex-full.png"
    end

    test "does not include a signature footer" do
      refute package_published_email().html_body =~ "Hex.pm"
    end

    test "renders without endpoint runtime state" do
      endpoint_key = {Phoenix.Endpoint, HexpmWeb.Endpoint}
      endpoint_state = :persistent_term.get(endpoint_key)
      :persistent_term.erase(endpoint_key)

      on_exit(fn -> :persistent_term.put(endpoint_key, endpoint_state) end)

      email = Emails.password_reset_request(build(:user), %{key: "abc"})

      assert email.html_body =~ "http://localhost:5000/images/hex-full.png"
      assert email.html_body =~ "http://localhost:5000/password/new"
    end
  end

  describe "code blocks" do
    test "render inside table cells instead of divs" do
      emails = [
        package_published_email(),
        Emails.organization_invite(%Organization{name: "acme"}, build(:user)),
        Emails.password_reset_request(build(:user), %{key: "abc"}),
        Emails.security_password_reset(build(:user), %{key: "abc"}),
        Emails.typosquat_candidates([["foo", "phoo", 1]], 2)
      ]

      for email <- emails do
        refute email.html_body =~ "<div"
      end
    end
  end

  describe "security_password_reset/2" do
    test "matches the styled email design" do
      email = Emails.security_password_reset(build(:user), %{key: "abc"})
      document = Floki.parse_document!(email.html_body)

      assert [_title] = Floki.find(document, "h1")
      assert Floki.find(document, "p pre") == []

      assert Enum.any?(Floki.find(document, "a"), fn {"a", attrs, _children} ->
               (Map.new(attrs)["href"] || "") =~ "/password/new"
             end)
    end
  end

  describe "SSO security notifications" do
    setup do
      user = insert(:user)

      insert(:email,
        user: user,
        email: "secondary@example.com",
        primary: false,
        public: false,
        gravatar: false
      )

      %{
        organization: build(:organization, name: "acme"),
        user: Hexpm.Repo.preload(user, :emails, force: true)
      }
    end

    test "link and unlink notifications go to every account email", context do
      for email <- [
            Emails.sso_identity_linked(context.organization, context.user),
            Emails.sso_identity_unlinked(context.organization, context.user)
          ] do
        assert Enum.sort(Enum.map(email.to, &elem(&1, 1))) ==
                 Enum.sort(["secondary@example.com", User.email(context.user, :primary)])

        assert email.text_body =~ "acme"
      end
    end

    test "email mismatch identifies the provider address", context do
      email = Emails.sso_email_mismatch(context.organization, context.user, "person@idp.example")

      assert email.text_body =~ "person@idp.example"
      assert email.text_body =~ "no account email was changed"
    end
  end

  describe "links" do
    test "Common.link emits anchors with explicit styles" do
      html = Common.link("https://example.com", "click", :html)

      assert html =~ ~s(href="https://example.com")
      assert html =~ "color: #0f59d8"
      assert html =~ "text-decoration: none"
    end

    test "helpers returning html render as html instead of escaped text" do
      emails = [
        Emails.password_reset_request(build(:user), %{key: "abc"}),
        Emails.security_password_reset(build(:user), %{key: "abc"})
      ]

      for email <- emails do
        refute email.html_body =~ "&lt;a"
      end
    end
  end
end
