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
    plug :fetch_body
    plug :read_body_finally
  end

  pipeline :api do
    plug :accepts, @accepted_formats
    plug HexWeb.BlockAddress.Plug
    plug HexWeb.RateLimit.Plug
  end

  scope "/", HexWeb do
    pipe_through :browser

    get  "/",                       PageController,     :index

    get  "password/reset",          PasswordController, :show_reset
    post "password/reset",          PasswordController, :reset
    get  "password/confirm",        PasswordController, :show_confirm

    get  "docs/usage",              DocsController,     :show_usage
    get  "docs/rebar3_usage",       DocsController,     :show_rebar3_usage
    get  "docs/publish",            DocsController,     :show_publish
    get  "docs/rebar3_publish",     DocsController,     :show_rebar3_publish
    get  "docs/tasks",              DocsController,     :show_tasks
    get  "docs/codeofconduct",      DocsController,     :show_coc
    get  "docs/faq",                DocsController,     :show_faq
    get  "docs/mirrors",            DocsController,     :show_mirrors

    get  "packages",                PackageController,  :index
    get  "packages/:name",          PackageController,  :show
    get  "packages/:name/:version", PackageController,  :show
  end

  scope "/", HexWeb do
    get "installs/hex.ez", InstallerController, :get_archive

    # TODO: Check if we can replace this
    if Mix.env in [:dev, :test, :hex] do
      get "registry.ets.gz",              TestController, :get_registry
      get "registry.ets.gz.signed",       TestController, :get_registry_signed
      get "tarballs/:ball",               TestController, :get_tarball
      get "docs/:package/:version/*page", TestController, :get_docs_page
    end
  end

  scope "/api", HexWeb.API do
    pipe_through :upload

    post "packages/:name/releases",               ReleaseController, :create
    post "packages/:name/releases/:version/docs", DocsController,    :create
  end

  scope "/api", HexWeb.API do
    pipe_through :api

    post   "users",                                 UserController,    :create
    get    "users/:name",                           UserController,    :show
    post   "users/:name/reset",                     UserController,    :reset

    get    "packages",                              PackageController, :index
    get    "packages/:name",                        PackageController, :show

    get    "packages/:name/releases/:version",      ReleaseController, :show
    delete "packages/:name/releases/:version",      ReleaseController, :delete

    delete "packages/:name/releases/:version/docs", DocsController,    :delete

    get    "packages/:name/owners",                 OwnerController,   :index
    get    "packages/:name/owners/:email",          OwnerController,   :show
    put    "packages/:name/owners/:email",          OwnerController,   :create
    delete "packages/:name/owners/:email",          OwnerController,   :delete

    get    "keys",                                  KeyController,     :index
    get    "keys/:name",                            KeyController,     :show
    post   "keys",                                  KeyController,     :create
    delete "keys/:name",                            KeyController,     :delete
  end
end
