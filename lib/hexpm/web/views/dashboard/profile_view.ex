defmodule HexpmWeb.Dashboard.ProfileView do
  use HexpmWeb, :view
  alias HexpmWeb.DashboardView

  import HexpmWeb.Dashboard.EmailView,
    only: [
      public_email_options: 1,
      public_email_value: 1,
      gravatar_email_options: 1,
      gravatar_email_value: 1
    ]
end
