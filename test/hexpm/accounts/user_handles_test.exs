defmodule Hexpm.Accounts.UserHandlesTest do
  use Hexpm.DataCase, async: true

  alias Hexpm.Accounts.UserHandles

  describe "render/1" do
    test "handles with https schema" do
      user =
        build(:user,
          handles:
            build(:user_handles,
              twitter: "https://twitter.com/eric",
              github: "https://github.com/eric",
              elixirforum: "https://elixirforum.com/u/eric",
              freenode: "freenode",
              slack: "slack"
            )
        )

      assert UserHandles.render(user) ==
               [
                 {"Twitter", "eric", "https://twitter.com/eric"},
                 {"GitHub", "eric", "https://github.com/eric"},
                 {"Elixir Forum", "eric", "https://elixirforum.com/u/eric"},
                 {"Libera", "freenode", "irc://irc.libera.chat/elixir"},
                 {"Slack", "slack", "https://elixir-slackin.herokuapp.com/"}
               ]
    end

    test "handles with http schema" do
      user =
        build(:user,
          handles:
            build(:user_handles,
              twitter: "http://twitter.com/eric",
              github: "http://github.com/eric",
              elixirforum: "http://elixirforum.com/u/eric",
              freenode: "freenode",
              slack: "slack"
            )
        )

      assert UserHandles.render(user) ==
               [
                 {"Twitter", "eric", "https://twitter.com/eric"},
                 {"GitHub", "eric", "https://github.com/eric"},
                 {"Elixir Forum", "eric", "https://elixirforum.com/u/eric"},
                 {"Libera", "freenode", "irc://irc.libera.chat/elixir"},
                 {"Slack", "slack", "https://elixir-slackin.herokuapp.com/"}
               ]
    end

    test "handles with without scheme" do
      user =
        build(:user,
          handles:
            build(:user_handles,
              twitter: "twitter.com/eric",
              github: "github.com/eric",
              elixirforum: "elixirforum.com/u/eric",
              freenode: "freenode",
              slack: "slack"
            )
        )

      assert UserHandles.render(user) ==
               [
                 {"Twitter", "eric", "https://twitter.com/eric"},
                 {"GitHub", "eric", "https://github.com/eric"},
                 {"Elixir Forum", "eric", "https://elixirforum.com/u/eric"},
                 {"Libera", "freenode", "irc://irc.libera.chat/elixir"},
                 {"Slack", "slack", "https://elixir-slackin.herokuapp.com/"}
               ]
    end

    test "handle with full URL" do
      user = build(:user, handles: build(:user_handles, twitter: "https://example.com"))
      assert UserHandles.render(user) == []
    end
  end
end
