defmodule HexWeb.Router do
  use HexWeb.Web, :router

  @accepted_formats ~w(json elixir erlang)

  pipeline :browser do
    plug :accepts, ["html"]
    plug :auth_gate
    plug :fetch_session
    plug :fetch_flash
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    plug :web_user_agent
    plug :login
  end

  pipeline :upload do
    plug :accepts, @accepted_formats
    plug :auth_gate
    plug :user_agent
    plug :fetch_body
    plug :read_body_finally
  end

  pipeline :api do
    plug :accepts, @accepted_formats
    plug :auth_gate
    plug :user_agent
    plug HexWeb.BlockAddress.Plug
    plug HexWeb.RateLimit.Plug
  end

  scope "/", HexWeb do
    pipe_through :browser

    get  "/",                               PageController, :index
    get  "/sponsors",                       PageController, :sponsors
    get  "/.well-known/acme-challenge/:id", PageController, :letsencrypt

    get  "/login",  LoginController, :show
    post "/login",  LoginController, :create
    post "/logout", LoginController, :delete

    get  "/signup",  SignupController, :show
    post "/signup",  SignupController, :create

    get  "/password/new", PasswordController, :show
    post "/password/new", PasswordController, :update

    get  "/password/reset", PasswordResetController, :show
    post "/password/reset", PasswordResetController, :create

    get  "/email/verify", EmailController, :verify

    get  "/users/:username", UserController, :show

    get    "/dashboard",               DashboardController, :index
    get    "/dashboard/profile",       DashboardController, :profile
    post   "/dashboard/profile",       DashboardController, :update_profile
    get    "/dashboard/password",      DashboardController, :password
    post   "/dashboard/password",      DashboardController, :update_password
    get    "/dashboard/email",         DashboardController, :email
    post   "/dashboard/email",         DashboardController, :add_email
    delete "/dashboard/email",         DashboardController, :remove_email
    post   "/dashboard/email/primary", DashboardController, :primary_email
    post   "/dashboard/email/public",  DashboardController, :public_email
    post   "/dashboard/email/resend",  DashboardController, :resend_verify_email

    get  "/docs/usage",          DocsController, :usage
    get  "/docs/rebar3_usage",   DocsController, :rebar3_usage
    get  "/docs/publish",        DocsController, :publish
    get  "/docs/rebar3_publish", DocsController, :rebar3_publish
    get  "/docs/tasks",          DocsController, :tasks
    get  "/docs/faq",            DocsController, :faq
    get  "/docs/mirrors",        DocsController, :mirrors
    get  "/docs/public_keys",    DocsController, :public_keys

    get  "/policies",                PolicyController, :index
    get  "/policies/codeofconduct",  PolicyController, :coc
    get  "/policies/privacy",        PolicyController, :privacy
    get  "/policies/termsofservice", PolicyController, :tos
    get  "/policies/copyright",      PolicyController, :copyright

    get  "/packages",                PackageController, :index
    get  "/packages/:name",          PackageController, :show
    get  "/packages/:name/:version", PackageController, :show
  end

  scope "/", HexWeb do
    get "/sitemap.xml",     SitemapController,    :sitemap
    get "/hexsearch.xml",   OpenSearchController, :opensearch
    get "/installs/hex.ez", InstallController,    :archive
  end

  if Mix.env in [:dev, :test, :hex] do
    scope "/repo", HexWeb do
      get "/registry.ets.gz",        TestController, :registry
      get "/registry.ets.gz.signed", TestController, :registry_signed
      get "/names",                  TestController, :names
      get "/versions",               TestController, :version
      get "/packages/:package",      TestController, :package
      get "/tarballs/:ball",         TestController, :tarball
      get "/installs/hex-1.x.csv",   TestController, :installs_csv
    end

    scope "/docs", HexWeb do
      get "/:package/:version/*page", TestController, :docs_page
      get "/sitemap.xml",             TestController, :docs_sitemap
    end
  end

  scope "/api", HexWeb.API, as: :api do
    pipe_through :upload

    post "/packages/:name/releases",               ReleaseController, :create
    post "/packages/:name/releases/:version/docs", DocsController,    :create
  end

  scope "/api", HexWeb.API, as: :api do
    pipe_through :api

    post   "/users",             UserController, :create
    get    "/users/:name",       UserController, :show
    get    "/users/:name/test",  UserController, :test
    post   "/users/:name/reset", UserController, :reset

    get    "/packages",       PackageController, :index
    get    "/packages/:name", PackageController, :show

    get    "/packages/:name/releases/:version", ReleaseController, :show
    delete "/packages/:name/releases/:version", ReleaseController, :delete

    # Temporary, see #232
    get    "/packages/:name/releases/:version/docs", DocsController, :show
    delete "/packages/:name/releases/:version/docs", DocsController, :delete

    get    "/packages/:name/owners",        OwnerController, :index
    get    "/packages/:name/owners/:email", OwnerController, :show
    put    "/packages/:name/owners/:email", OwnerController, :create
    delete "/packages/:name/owners/:email", OwnerController, :delete

    get    "/keys",       KeyController, :index
    get    "/keys/:name", KeyController, :show
    post   "/keys",       KeyController, :create
    delete "/keys",       KeyController, :delete_all
    delete "/keys/:name", KeyController, :delete
  end
end
