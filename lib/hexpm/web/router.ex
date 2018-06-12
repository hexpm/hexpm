defmodule Hexpm.Web.Router do
  use Hexpm.Web, :router
  use Plug.ErrorHandler

  @accepted_formats ~w(json elixir erlang)

  pipeline :browser do
    plug :accepts, ["html"]
    plug :auth_gate
    plug :fetch_session
    plug :fetch_flash
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    plug :web_user_agent
    plug :validate_url
    plug :login
    plug :default_repository
  end

  pipeline :upload do
    plug :read_body_finally
    plug :accepts, @accepted_formats
    plug :auth_gate
    plug :user_agent
    plug :authenticate
    plug :validate_url
    plug Hexpm.Web.Plugs.Attack
    plug :fetch_body
    plug :default_repository
  end

  pipeline :api do
    plug :accepts, @accepted_formats
    plug :auth_gate
    plug :user_agent
    plug :authenticate
    plug :validate_url
    plug Hexpm.Web.Plugs.Attack
    plug Corsica, origins: "*", allow_methods: ["HEAD", "GET"]
    plug :default_repository
  end

  if Mix.env() == :dev do
    forward "/sent_emails", Bamboo.EmailPreviewPlug
  end

  scope "/", Hexpm.Web do
    pipe_through :browser

    get "/", PageController, :index
    get "/about", PageController, :about
    get "/pricing", PageController, :pricing
    get "/sponsors", PageController, :sponsors

    get "/login", LoginController, :show
    post "/login", LoginController, :create
    post "/logout", LoginController, :delete

    get "/signup", SignupController, :show
    post "/signup", SignupController, :create

    get "/password/new", PasswordController, :show
    post "/password/new", PasswordController, :update

    get "/password/reset", PasswordResetController, :show
    post "/password/reset", PasswordResetController, :create

    get "/email/verify", EmailVerificationController, :verify
    get "/email/verification", EmailVerificationController, :show
    post "/email/verification", EmailVerificationController, :create

    get "/dashboard", DashboardController, :index

    get "/users/:username", UserController, :show

    get "/docs", DocsController, :index
    get "/docs/usage", DocsController, :usage
    get "/docs/publish", DocsController, :publish
    get "/docs/tasks", DocsController, :tasks
    get "/docs/rebar3_usage", DocsController, :rebar3_usage
    get "/docs/rebar3_publish", DocsController, :rebar3_publish
    get "/docs/rebar3_tasks", DocsController, :rebar3_tasks
    get "/docs/private", DocsController, :private
    get "/docs/faq", DocsController, :faq
    get "/docs/mirrors", DocsController, :mirrors
    get "/docs/public_keys", DocsController, :public_keys

    get "/policies/codeofconduct", PolicyController, :coc
    get "/policies/privacy", PolicyController, :privacy
    get "/policies/termsofservice", PolicyController, :tos
    get "/policies/copyright", PolicyController, :copyright
    get "/policies/dispute", PolicyController, :dispute

    get "/packages", PackageController, :index
    get "/packages/:name", PackageController, :show
    get "/packages/:name/:version", PackageController, :show
    get "/packages/:repository/:name/:version", PackageController, :show

    get "/blog", BlogController, :index
    get "/blog/:slug", BlogController, :show
  end

  scope "/dashboard", Hexpm.Web.Dashboard do
    pipe_through :browser

    get "/profile", ProfileController, :index
    post "/profile", ProfileController, :update

    get "/password", PasswordController, :index
    post "/password", PasswordController, :update

    get "/email", EmailController, :index
    post "/email", EmailController, :create
    delete "/email", EmailController, :delete
    post "/email/primary", EmailController, :primary
    post "/email/public", EmailController, :public
    post "/email/resend", EmailController, :resend_verify
    post "/email/gravatar", EmailController, :gravatar

    get "/repos/:dashboard_repo", RepositoryController, :show
    post "/repos/:dashboard_repo", RepositoryController, :update
    post "/repos/:dashboard_repo/billing-token", RepositoryController, :billing_token
    post "/repos/:dashboard_repo/cancel-billing", RepositoryController, :cancel_billing
    post "/repos/:dashboard_repo/update-billing", RepositoryController, :update_billing
    post "/repos/:dashboard_repo/create-billing", RepositoryController, :create_billing
    get "/repos/:dashboard_repo/invoices/:id", RepositoryController, :show_invoice
    post "/repos/:dashboard_repo/invoices/:id/pay", RepositoryController, :pay_invoice
    get "/repos", RepositoryController, :new
    post "/repos", RepositoryController, :create

    get "/keys", KeyController, :index
    delete "/keys", KeyController, :delete
    post "/keys", KeyController, :create
  end

  scope "/", Hexpm.Web do
    get "/sitemap.xml", SitemapController, :sitemap
    get "/hexsearch.xml", OpenSearchController, :opensearch
    get "/installs/hex.ez", InstallController, :archive
  end

  scope "/api", Hexpm.Web.API, as: :api do
    pipe_through :upload

    for prefix <- ["/", "/repos/:repository"] do
      scope prefix do
        post "/publish", ReleaseController, :publish
        post "/packages/:name/releases", ReleaseController, :create
        post "/packages/:name/releases/:version/docs", DocsController, :create
      end
    end
  end

  scope "/api", Hexpm.Web.API, as: :api do
    pipe_through :api

    get "/", IndexController, :index

    post "/users", UserController, :create
    get "/users/me", UserController, :me
    get "/users/:name", UserController, :show
    # NOTE: Deprecated (2018-05-21)
    get "/users/:name/test", UserController, :test
    post "/users/:name/reset", UserController, :reset

    get "/repos", RepositoryController, :index
    get "/repos/:repository", RepositoryController, :show

    for prefix <- ["/", "/repos/:repository"] do
      scope prefix do
        get "/packages", PackageController, :index
        get "/packages/:name", PackageController, :show

        get "/packages/:name/releases/:version", ReleaseController, :show
        delete "/packages/:name/releases/:version", ReleaseController, :delete

        post "/packages/:name/releases/:version/retire", RetirementController, :create
        delete "/packages/:name/releases/:version/retire", RetirementController, :delete

        get "/packages/:name/releases/:version/docs", DocsController, :show
        delete "/packages/:name/releases/:version/docs", DocsController, :delete

        get "/packages/:name/owners", OwnerController, :index
        get "/packages/:name/owners/:email", OwnerController, :show
        put "/packages/:name/owners/:email", OwnerController, :create
        delete "/packages/:name/owners/:email", OwnerController, :delete
      end
    end

    get "/keys", KeyController, :index
    get "/keys/:name", KeyController, :show
    post "/keys", KeyController, :create
    delete "/keys", KeyController, :delete_all
    delete "/keys/:name", KeyController, :delete

    get "/auth", AuthController, :show
  end

  if Mix.env() in [:dev, :test, :hex] do
    scope "/repo", Hexpm.Web do
      get "/registry.ets.gz", TestController, :registry
      get "/registry.ets.gz.signed", TestController, :registry_signed
      get "/names", TestController, :names
      get "/versions", TestController, :version
      get "/installs/hex-1.x.csv", TestController, :installs_csv

      for prefix <- ["/", "/repos/:repository"] do
        scope prefix do
          get "/packages/:package", TestController, :package
          get "/tarballs/:ball", TestController, :tarball
        end
      end
    end

    scope "/api", Hexpm.Web do
      pipe_through :api

      post "/repo", TestController, :repo
    end

    scope "/docs", Hexpm.Web do
      get "/:package/:version/*page", TestController, :docs_page
      get "/sitemap.xml", TestController, :docs_sitemap
    end
  end

  defp handle_errors(conn, %{kind: kind, reason: reason, stack: stacktrace}) do
    if report?(kind, reason) do
      conn = maybe_fetch_params(conn)
      url = "#{conn.scheme}://#{conn.host}:#{conn.port}#{conn.request_path}"
      user_ip = conn.remote_ip |> :inet.ntoa() |> List.to_string()
      headers = conn.req_headers |> Map.new() |> filter_headers()
      params = filter_params(conn.params)
      endpoint_url = Hexpm.Web.Endpoint.config(:url)

      conn_data = %{
        "request" => %{
          "url" => url,
          "user_ip" => user_ip,
          "headers" => headers,
          "params" => params,
          "method" => conn.method
        },
        "server" => %{
          "host" => endpoint_url[:host],
          "root" => endpoint_url[:path]
        }
      }

      Rollbax.report(kind, reason, stacktrace, %{}, conn_data)
    end
  end

  defp report?(:error, exception), do: Plug.Exception.status(exception) == 500
  defp report?(_kind, _reason), do: true

  defp maybe_fetch_params(conn) do
    try do
      Plug.Conn.fetch_query_params(conn)
    rescue
      _ ->
        %{conn | params: "[UNFETCHED]"}
    end
  end

  @filter_headers ~w(authorization)

  defp filter_headers(headers) do
    Map.drop(headers, @filter_headers)
  end

  @filter_params ~w(password password_confirmation)

  defp filter_params(params) when is_map(params) do
    Map.new(params, fn {key, value} ->
      if key in @filter_params do
        {key, "[FILTERED]"}
      else
        {key, filter_params(value)}
      end
    end)
  end

  defp filter_params(params) when is_list(params) do
    Enum.map(params, &filter_params/1)
  end

  defp filter_params(other) do
    other
  end
end
