defmodule HexpmWeb.Dashboard.DeleteAccountView do
  use HexpmWeb, :view

  import HexpmWeb.Components.Buttons, only: [button: 1]
  import HexpmWeb.Components.Form, only: [sudo_form: 1]
  import HexpmWeb.Components.Input, only: [text_input: 1]

  def username_pattern(username) do
    String.replace(username, ".", "\\.")
  end
end
