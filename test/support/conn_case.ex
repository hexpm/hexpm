defmodule HexpmWeb.ConnCase do
  @moduledoc """
  This module defines the test case to be used by
  tests that require setting up a connection.

  Such tests rely on `Phoenix.ConnTest` and also
  imports other functionality to make it easier
  to build and query models.

  Finally, if the test case interacts with the database,
  it cannot be async. For this reason, every test runs
  inside a transaction which is reset at the beginning
  of the test unless the test case is marked as async.
  """

  use ExUnit.CaseTemplate

  using do
    quote do
      # Import conveniences for testing with connections
      alias Hexpm.{Fake, Repo}
      alias HexpmWeb.Router.Helpers, as: Routes

      import Ecto
      import Ecto.Query, only: [from: 2]
      import Plug.Conn
      import Phoenix.ConnTest
      import Mox
      import Hexpm.{Factory, TestHelpers}
      import unquote(__MODULE__)

      # The default endpoint for testing
      @endpoint HexpmWeb.Endpoint

      use HexpmWeb, :verified_routes
    end
  end

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Hexpm.RepoBase)
    Bamboo.SentEmail.reset()
    :ok
  end

  def test_login(conn, user) do
    Plug.Test.init_test_session(conn, %{"user_id" => user.id})
  end

  def last_session() do
    import Ecto.Query

    from(s in Hexpm.Accounts.Session, order_by: [desc: s.id], limit: 1)
    |> Hexpm.Repo.one()
  end

  def json_post(conn, path, params) do
    conn
    |> Plug.Conn.put_req_header("content-type", "application/json")
    |> Phoenix.ConnTest.dispatch(HexpmWeb.Endpoint, :post, path, Jason.encode!(params))
  end

  def mock_captcha_success(_context \\ %{}) do
    mock_captcha(true)
    :ok
  end

  def mock_captcha_failure(_context \\ %{}) do
    mock_captcha(false)
    :ok
  end

  def mock_captcha(success) do
    Mox.expect(
      Hexpm.HTTP.Mock,
      :post,
      fn "https://hcaptcha.com/siteverify", headers, params ->
        assert headers == [{"content-type", "application/x-www-form-urlencoded"}]
        assert params == %{response: "captcha", secret: "secret"}
        {:ok, 200, [{"content-type", "application/json"}], %{"success" => success}}
      end
    )
  end
end
