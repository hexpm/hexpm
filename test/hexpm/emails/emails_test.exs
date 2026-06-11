defmodule Hexpm.EmailsTest do
  use Hexpm.DataCase, async: true

  alias Hexpm.Emails

  describe "html layout header" do
    test "does not rely on flexbox" do
      email = Emails.package_published([build(:user)], build(:user), "cowboy", "2.16.1")

      refute email.html_body =~ "display: flex"
    end

    test "wordmark is a link with explicit white color and no underline" do
      email = Emails.package_published([build(:user)], build(:user), "cowboy", "2.16.1")

      assert [{"a", attrs, _children}] =
               email.html_body
               |> Floki.parse_document!()
               |> Floki.find("a")
               |> Enum.filter(&(&1 |> Floki.text() |> String.trim() == "hex.pm"))

      attrs = Map.new(attrs)
      assert attrs["href"] == HexpmWeb.Endpoint.url() <> "/"
      assert attrs["style"] =~ "color: #ffffff"
      assert attrs["style"] =~ "text-decoration: none"
    end
  end
end
