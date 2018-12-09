defmodule HexpmWeb.API.ReleaseViewTest do
  use HexpmWeb.ConnCase, async: true

  alias HexpmWeb.API.ReleaseView

  import Hexpm.Factory

  describe "show.json" do
    test "includes publisher info" do
      publisher =
        build(:user,
          username: "Publisher",
          emails: [build(:email, email: "publisher@example.com", public: true)]
        )

      release =
        build(:release,
          package: build(:package),
          requirements: [],
          publisher: publisher
        )

      assert %{
               "publisher" => %{
                 "username" => "Publisher",
                 "email" => "publisher@example.com"
               }
             } = render_to_json(ReleaseView, "show.json", %{release: release})
    end
  end

  defp render_to_json(module, template, assign) do
    module
    |> Phoenix.View.render_to_string(template, assign)
    |> Jason.decode!()
  end
end
