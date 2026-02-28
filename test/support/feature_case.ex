if Code.ensure_loaded?(Wallaby) do
  defmodule HexpmWeb.FeatureCase do
    use ExUnit.CaseTemplate

    using do
      quote do
        use Wallaby.Feature
        import Wallaby.Query

        alias Hexpm.{Fake, Repo}

        import Ecto
        import Ecto.Query, only: [from: 2]
        import Mox
        import Hexpm.{Factory, TestHelpers}
        import HexpmWeb.IntegrationHelpers
        import HexpmWeb.FeatureCase

        @endpoint HexpmWeb.Endpoint

        use HexpmWeb, :verified_routes
      end
    end

    setup do
      {:ok, _} = Application.ensure_all_started(:wallaby)
      base_url = ensure_endpoint_server()
      Application.put_env(:wallaby, :base_url, base_url)

      :ok = Ecto.Adapters.SQL.Sandbox.checkout(Hexpm.RepoBase)
      Ecto.Adapters.SQL.Sandbox.mode(Hexpm.RepoBase, {:shared, self()})
      Mox.set_mox_global()
      Bamboo.SentEmail.reset()

      metadata = Phoenix.Ecto.SQL.Sandbox.metadata_for(Hexpm.RepoBase, self())
      {:ok, session} = Wallaby.start_session(metadata: metadata)

      {:ok, session: session}
    end

    # Ensures the endpoint HTTP server is running for browser tests.
    # The test config has server: false to avoid starting it for unit tests.
    # Starts cowboy on a free port and returns the base URL.
    defp ensure_endpoint_server do
      port =
        try do
          :ranch.get_port(HexpmWeb.Endpoint.HTTP)
        rescue
          _ ->
            {:ok, _} = Plug.Cowboy.http(HexpmWeb.Endpoint, [], port: 0)
            :ranch.get_port(HexpmWeb.Endpoint.HTTP)
        end

      "http://localhost:#{port}"
    end

    @doc """
    Logs in the user via the browser login form.
    The user's password is assumed to be "password" (from Factory).
    """
    def browser_login(session, user) do
      import Wallaby.Browser
      import Wallaby.Query

      Mox.stub(Hexpm.Pwned.Mock, :password_breached?, fn _password -> false end)

      session
      |> visit("/login")
      |> fill_in(css("#username"), with: user.username)
      |> fill_in(css("#password"), with: "password")
      |> click(button("Log in"))
    end
  end
end
