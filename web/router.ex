defmodule HexWeb.Router do
  use HexWeb.Web, :router

  @accepted_formats ~w(json elixir erlang)

  pipeline :browser do
    plug :accepts, ["html"]
    # plug :fetch_flash
    plug :put_secure_browser_headers
  end

  pipeline :upload do
    plug :accepts, @accepted_formats
    plug :user_agent
    plug :fetch_body
    plug :read_body_finally
  end

  pipeline :api do
    plug :accepts, @accepted_formats
    plug :user_agent
    plug HexWeb.BlockAddress.Plug
    plug HexWeb.RateLimit.Plug
  end

  scope "/", HexWeb do
    pipe_through :browser

    get  "/",                        PageController,     :index
    get  "/sponsors",                PageController,     :sponsors

    get  "/password/reset",          PasswordController, :reset
    get  "/password/new",            PasswordController, :new
    post "/password/choose",         PasswordController, :choose
    get "/password/choose",         PasswordController, :choose

    get  "/docs/usage",              DocsController,     :usage
    get  "/docs/rebar3_usage",       DocsController,     :rebar3_usage
    get  "/docs/publish",            DocsController,     :publish
    get  "/docs/rebar3_publish",     DocsController,     :rebar3_publish
    get  "/docs/tasks",              DocsController,     :tasks
    get  "/docs/faq",                DocsController,     :faq
    get  "/docs/mirrors",            DocsController,     :mirrors
    get  "/docs/public_keys",        DocsController,     :public_keys

    get  "/policies",                PolicyController,   :index
    get  "/policies/codeofconduct",  PolicyController,   :coc
    get  "/policies/privacy",        PolicyController,   :privacy
    get  "/policies/termsofservice", PolicyController,   :tos
    get  "/policies/copyright",      PolicyController,   :copyright

    get  "/packages",                PackageController,  :index
    get  "/packages/:name",          PackageController,  :show
    get  "/packages/:name/:version", PackageController,  :show

    get "/login",                    LoginController,    :login
    get "/signup",                   LoginController,    :signup
    get "/confirm",                  LoginController,    :confirm
  end

  scope "/", HexWeb do
    get "/sitemap.xml",     SitemapController,    :sitemap
    get "/hexsearch.xml",   OpenSearchController, :opensearch
    get "/installs/hex.ez", InstallController,  :get_archive
  end

  if Mix.env in [:dev, :test, :hex] do
    scope "/repo", HexWeb do
      get "/registry.ets.gz",        TestController, :get_registry
      get "/registry.ets.gz.signed", TestController, :get_registry_signed
      get "/names",                  TestController, :get_names
      get "/versions",               TestController, :get_version
      get "/packages/:package",      TestController, :get_package
      get "/tarballs/:ball",         TestController, :get_tarball
      get "/installs/hex-1.x.csv",   TestController, :get_installs_csv
    end

    scope "/docs", HexWeb do
      get "/:package/:version/*page", TestController, :get_docs_page
      get "/sitemap.xml",             TestController, :get_docs_sitemap
    end
  end

  unless Application.get_env(:hex_web, :read_only) do

    scope "/api", HexWeb.API do
      pipe_through :upload

      post "/packages/:name/releases",               ReleaseController, :create
      post "/packages/:name/releases/:version/docs", DocsController,    :create
    end

    scope "/api", HexWeb.API do
      pipe_through :api

      post   "/users",                                 UserController,    :create
      get    "/users/:name",                           UserController,    :show
      post   "/users/:name/reset",                     UserController,    :reset

      get    "/packages",                              PackageController, :index
      get    "/packages/:name",                        PackageController, :show

      get    "/packages/:name/releases/:version",      ReleaseController, :show
      delete "/packages/:name/releases/:version",      ReleaseController, :delete

      # Temporary, see #232
      get    "/packages/:name/releases/:version/docs", DocsController,    :show
      delete "/packages/:name/releases/:version/docs", DocsController,    :delete

      get    "/packages/:name/owners",                 OwnerController,   :index
      get    "/packages/:name/owners/:email",          OwnerController,   :show
      put    "/packages/:name/owners/:email",          OwnerController,   :create
      delete "/packages/:name/owners/:email",          OwnerController,   :delete

      get    "/keys",                                  KeyController,     :index
      get    "/keys/:name",                            KeyController,     :show
      post   "/keys",                                  KeyController,     :create
      delete "/keys",                                  KeyController,     :delete_all
      delete "/keys/:name",                            KeyController,     :delete
    end

  end
end
