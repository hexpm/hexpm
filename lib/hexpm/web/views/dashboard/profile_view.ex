defmodule Hexpm.Web.Dashboard.ProfileView do
  use Hexpm.Web, :view
  alias Hexpm.Web.DashboardView

  import Hexpm.Web.Dashboard.EmailView,
    only: [
      public_email_options: 1,
      public_email_value: 1,
      gravatar_email_options: 1,
      gravatar_email_value: 1
    ]
end
