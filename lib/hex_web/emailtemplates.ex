defmodule HexWeb.EmailTemplates do

  def confirmed do
    """
    Welcome to Hex.pm!

    You now have full access to your Hex account.

    Enjoy!

    The Hex.pm Team
    """ |> String.replace("\n", "\r\n")
  end

  def confirmation_request(opts) do
    username = Keyword.get(opts, :username)
    key = Keyword.get(opts, :key)

    """
    Welcome to Hex.pm!

    To begin using your account, we require you to verify your email address.

    You can do so by running the following command on a system where Hex is installed:

      mix hex.user confirm #{username} #{key}

    Once this is complete, you will have full access to your Hex account.

    Thanks!

    The Hex.pm Team

    """ |> String.replace("\n", "\r\n")
  end

end
