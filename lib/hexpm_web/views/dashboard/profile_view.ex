defmodule HexpmWeb.Dashboard.ProfileView do
  use HexpmWeb, :view

  import HexpmWeb.Dashboard.EmailView,
    only: [
      public_email_options: 1,
      public_email_value: 1,
      gravatar_email_options: 1,
      gravatar_email_value: 1
    ]

  import HexpmWeb.Components.SocialInput, only: [social_input: 1]
  import HexpmWeb.Components.Buttons, only: [button: 1, text_link: 1]
  import HexpmWeb.Components.Input, only: [text_input: 1, select_input: 1]
end
