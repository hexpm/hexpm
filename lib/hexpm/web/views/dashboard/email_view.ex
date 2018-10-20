defmodule HexpmWeb.Dashboard.EmailView do
  use HexpmWeb, :view
  alias HexpmWeb.DashboardView

  def public_email_options(user) do
    emails =
      user.emails
      |> Email.order_emails()
      |> Enum.filter(& &1.verified)
      |> Enum.map(&{&1.email, &1.email})

    [{"Don't show a public email address", "none"}] ++ emails
  end

  def public_email_value(user) do
    User.email(user, :public) || "none"
  end

  def gravatar_email_options(user) do
    emails =
      user.emails
      |> Enum.filter(& &1.verified)
      |> Enum.map(&{&1.email, &1.email})

    [{"Don't show an avatar", "none"}] ++ emails
  end

  def gravatar_email_value(user) do
    User.email(user, :gravatar) || "none"
  end
end
