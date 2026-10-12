defmodule Hexpm.Accounts.UsersMailFailureTest do
  # Swaps the global mail adapter for one that refuses every mail.
  use Hexpm.DataCase, async: false

  alias Hexpm.Accounts.Users
  alias Hexpm.Emails

  @audit %{user: nil, user_agent: "TEST", remote_ip: "127.0.0.1", auth_credential: nil}

  setup do
    mailer = Application.fetch_env!(:hexpm, Emails.Mailer)

    Application.put_env(
      :hexpm,
      Emails.Mailer,
      Keyword.put(mailer, :adapter, Emails.FailingAdapter)
    )

    on_exit(fn -> Application.put_env(:hexpm, Emails.Mailer, mailer) end)

    ref = :telemetry_test.attach_event_handlers(self(), [[:hexpm, :accounts, :user_created]])
    on_exit(fn -> :telemetry.detach(ref) end)

    %{ref: ref}
  end

  test "counts a new account whose verification mail raised", %{ref: ref} do
    username = Hexpm.Fake.sequence(:username)
    params = %{"username" => username, "emails" => [%{"email" => Hexpm.Fake.sequence(:email)}]}

    assert_raise Swoosh.DeliveryError, fn -> Users.add(params, audit: @audit) end

    assert Users.get(username)
    assert_received {[:hexpm, :accounts, :user_created], ^ref, %{count: 1}, %{}}
  end

  test "counts a new unconfirmed OAuth account whose verification mail raised", %{ref: ref} do
    username = Hexpm.Fake.sequence(:username)

    assert_raise Swoosh.DeliveryError, fn ->
      Users.add_from_oauth_with_provider(
        username,
        Hexpm.Fake.sequence(:full_name),
        Hexpm.Fake.sequence(:email),
        "github",
        "12345",
        audit: @audit,
        confirmed?: false
      )
    end

    assert Users.get(username)
    assert_received {[:hexpm, :accounts, :user_created], ^ref, %{count: 1}, %{}}
  end
end
