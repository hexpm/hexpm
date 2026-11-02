defmodule HexpmWeb.EmailViewTest do
  use Hexpm.DataCase, async: true

  alias Hexpm.Emails
  alias HexpmWeb.EmailView.Common

  describe "Common.strong/2" do
    test "escapes and bolds a name for the HTML part" do
      assert Common.strong("a<b&c", :html) == "<strong>a&lt;b&amp;c</strong>"
    end

    test "leaves a name as it is for the text part" do
      assert Common.strong("a<b&c", :text) == "a<b&c"
    end
  end

  describe "names in email sentences" do
    test "are bold in the HTML part and plain in the text part" do
      email =
        Emails.package_published(
          [build(:user)],
          build(:user, username: "alice"),
          "cowboy",
          Version.parse!("2.16.1")
        )

      assert email.html_body =~
               "Package <strong>cowboy</strong> v2.16.1 was recently published by " <>
                 "<strong>alice</strong>."

      assert email.text_body =~
               "Package cowboy v2.16.1 was recently published by alice.\n" <>
                 "If this wasn't done by you or one of the other package owners"

      refute email.text_body =~ "<strong>"
    end

    test "are escaped in the HTML part" do
      email =
        Emails.owner_added(%{name: "<plug>"}, [build(:user)], build(:user, username: "a&b"), [])

      assert email.html_body =~
               "<strong>a&amp;b</strong> has been added as an owner to package " <>
                 "<strong>&lt;plug&gt;</strong>."

      refute email.html_body =~ "<plug>"
      assert email.text_body =~ "a&b has been added as an owner to package <plug>."
    end
  end
end
