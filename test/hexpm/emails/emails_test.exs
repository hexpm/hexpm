defmodule Hexpm.EmailsTest do
  use Hexpm.DataCase, async: true

  alias Hexpm.Accounts.Organization
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
      assert attrs["href"] == HexpmWeb.Endpoint.url() <> "/"
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

    test "footer wordmark is a link with explicit color and no underline" do
      assert [{"a", attrs, _children}] =
               package_published_email().html_body
               |> Floki.parse_document!()
               |> Floki.find("a")
               |> Enum.filter(&(&1 |> Floki.text() |> String.trim() == "Hex.pm"))

      attrs = Map.new(attrs)
      assert attrs["style"] =~ "color: #304254"
      assert attrs["style"] =~ "text-decoration: none"
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
