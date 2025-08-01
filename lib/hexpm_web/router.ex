defmodule HexpmWeb.Router do
  use HexpmWeb, :router
  import Phoenix.LiveDashboard.Router
  alias Hexpm.Accounts.{Organization, User}

  @accepted_formats ~w(json elixir erlang)

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_flash
    # plug :protect_from_forgery
    plug :put_secure_browser_headers
    plug :user_agent, required: false
    plug :validate_url
    plug HexpmWeb.Plugs.Attack
    plug :login
    plug :disable_deactivated
    plug :default_repository
  end

  pipeline :upload do
    plug :read_body_finally
    plug :accepts, @accepted_formats
    plug :user_agent
    plug :authenticate
    plug :disable_deactivated
    plug :validate_url
    plug HexpmWeb.Plugs.Attack
    plug :fetch_body
    plug :default_repository
  end

  pipeline :api do
    plug :accepts, @accepted_formats
    plug :user_agent
    plug :authenticate
    plug :disable_deactivated
    plug :validate_url
    plug HexpmWeb.Plugs.Attack
    plug Corsica, origins: "*", allow_methods: ["HEAD", "GET"]
    plug :default_repository
  end

  pipeline :admin do
    plug HexpmWeb.Plugs.DashboardAuth
  end

  if Mix.env() == :dev do
    forward "/sent_emails", Bamboo.SentEmailViewerPlug
  end

  scope "/", HexpmWeb do
    pipe_through :browser

    get "/", PageController, :index
    get "/about", PageController, :about
    get "/pricing", PageController, :pricing
    get "/sponsors", PageController, :sponsors

    get "/login", LoginController, :show
    post "/login", LoginController, :create
    post "/logout", LoginController, :delete

    get "/tfa", TFAAuthController, :show
    post "/tfa", TFAAuthController, :create

    get "/tfa/recovery", TFARecoveryController, :show
    post "/tfa/recovery", TFARecoveryController, :create

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

    get "/orgs/:username", UserController, :show

    get "/docs", DocsController, :index
    get "/docs/usage", DocsController, :usage
    get "/docs/publish", DocsController, :publish
    get "/docs/tasks", DocsController, :tasks
    get "/docs/gleam-usage", DocsController, :gleam_usage
    get "/docs/rebar3-usage", DocsController, :rebar3_usage
    get "/docs/rebar3-publish", DocsController, :rebar3_publish
    get "/docs/rebar3-private", DocsController, :rebar3_private
    get "/docs/rebar3-tasks", DocsController, :rebar3_tasks
    get "/docs/private", DocsController, :private
    get "/docs/faq", DocsController, :faq
    get "/docs/mirrors", DocsController, :mirrors
    get "/docs/public-keys", DocsController, :public_keys
    get "/docs/self-hosting", DocsController, :self_hosting

    get "/policies/codeofconduct", PolicyController, :coc
    get "/policies/privacy", PolicyController, :privacy
    get "/policies/termsofservice", PolicyController, :tos
    get "/policies/copyright", PolicyController, :copyright
    get "/policies/dispute", PolicyController, :dispute

    get "/packages/:name/versions", VersionController, :index
    get "/packages/:repository/:name/versions", VersionController, :index

    get "/packages", PackageController, :index
    get "/packages/:name", PackageController, :show
    get "/packages/:name/audit-logs", PackageController, :audit_logs
    get "/packages/:name/:version", PackageController, :show
    get "/packages/:repository/:name/audit-logs", PackageController, :audit_logs
    get "/packages/:repository/:name/:version", PackageController, :show

    get "/blog", BlogController, :index
    get "/blog/:slug", BlogController, :show

    get "/l/:short_code", ShortURLController, :show

    get "/package_searches/download", PackageSearchController, :download

    if Application.compile_env!(:hexpm, [:features, :package_reports]) do
      get "/reports", PackageReportController, :index
      post "/reports", PackageReportController, :create
      get "/reports/new", PackageReportController, :new

      get "/reports/:id", PackageReportController, :show
      post "/reports/:id/accept", PackageReportController, :accept
      post "/reports/:id/reject", PackageReportController, :reject
      post "/reports/:id/solve", PackageReportController, :solve
      post "/reports/:id/unresolve", PackageReportController, :unresolve
      post "/reports/:id/comment", PackageReportController, :comment
    end
  end

  scope "/dashboard", HexpmWeb.Dashboard do
    pipe_through :browser

    get "/profile", ProfileController, :index
    post "/profile", ProfileController, :update

    get "/password", PasswordController, :index, as: :dashboard_password
    post "/password", PasswordController, :update, as: :dashboard_password

    get "/security", SecurityController, :index, as: :dashboard_security
    post "/security/enable-tfa", SecurityController, :enable_tfa, as: :dashboard_security
    post "/security/disable-tfa", SecurityController, :disable_tfa, as: :dashboard_security

    post "/security/rotate-recovery-codes", SecurityController, :rotate_recovery_codes,
      as: :dashboard_security

    post "/security/reset-auth-app", SecurityController, :reset_auth_app, as: :dashboard_security

    get "/tfa/setup", TFAAuthSetupController, :index, as: :dashboard_tfa_setup
    post "/tfa/setup", TFAAuthSetupController, :create, as: :dashboard_tfa_setup

    get "/email", EmailController, :index
    post "/email", EmailController, :create
    delete "/email", EmailController, :delete
    post "/email/primary", EmailController, :primary
    post "/email/public", EmailController, :public
    post "/email/resend", EmailController, :resend_verify
    post "/email/gravatar", EmailController, :gravatar

    get "/repos", OrganizationController, :redirect_repo
    get "/repos/*glob", OrganizationController, :redirect_repo
    get "/orgs", OrganizationController, :new
    post "/orgs", OrganizationController, :create
    get "/orgs/:dashboard_org", OrganizationController, :show
    post "/orgs/:dashboard_org", OrganizationController, :update
    get "/orgs/:dashboard_org/audit-logs", OrganizationController, :audit_logs
    post "/orgs/:dashboard_org/leave", OrganizationController, :leave
    post "/orgs/:dashboard_org/billing-token", OrganizationController, :billing_token
    post "/orgs/:dashboard_org/cancel-billing", OrganizationController, :cancel_billing
    post "/orgs/:dashboard_org/update-billing", OrganizationController, :update_billing
    post "/orgs/:dashboard_org/create-billing", OrganizationController, :create_billing
    post "/orgs/:dashboard_org/add-seats", OrganizationController, :add_seats
    post "/orgs/:dashboard_org/remove-seats", OrganizationController, :remove_seats
    post "/orgs/:dashboard_org/change-plan", OrganizationController, :change_plan
    post "/orgs/:dashboard_org/keys", OrganizationController, :create_key
    delete "/orgs/:dashboard_org/keys", OrganizationController, :delete_key
    get "/orgs/:dashboard_org/invoices/:id", OrganizationController, :show_invoice
    post "/orgs/:dashboard_org/invoices/:id/pay", OrganizationController, :pay_invoice
    post "/orgs/:dashboard_org/profile", OrganizationController, :update_profile

    get "/keys", KeyController, :index
    delete "/keys", KeyController, :delete
    post "/keys", KeyController, :create

    get "/audit-logs", AuditLogController, :index
  end

  scope "/", HexpmWeb do
    get "/sitemap.xml", SitemapController, :main
    get "/docs_sitemap.xml", SitemapController, :docs
    get "/preview_sitemap.xml", SitemapController, :preview
    get "/hexsearch.xml", OpenSearchController, :opensearch
    get "/installs/hex.ez", InstallController, :archive
    get "/feeds/blog.xml", FeedsController, :blog
  end

  scope "/api", HexpmWeb.API, as: :api do
    pipe_through :upload

    for prefix <- ["/", "/repos/:repository"] do
      scope prefix do
        post "/publish", ReleaseController, :publish
        post "/packages/:name/releases", ReleaseController, :create
        post "/packages/:name/releases/:version/docs", DocsController, :create
      end
    end
  end

  scope "/api", HexpmWeb.API, as: :api do
    pipe_through :api

    get "/", IndexController, :index

    post "/users", UserController, :create
    get "/users/me", UserController, :me
    get "/users/me/audit-logs", UserController, :audit_logs
    get "/users/:name", UserController, :show
    # NOTE: Deprecated (2018-05-21)
    get "/users/:name/test", UserController, :test
    post "/users/:name/reset", UserController, :reset

    get "/orgs", OrganizationController, :index
    get "/orgs/:organization", OrganizationController, :show
    post "/orgs/:organization", OrganizationController, :update
    get "/orgs/:organization/audit-logs", OrganizationController, :audit_logs

    get "/orgs/:organization/members", OrganizationUserController, :index
    post "/orgs/:organization/members", OrganizationUserController, :create
    get "/orgs/:organization/members/:name", OrganizationUserController, :show
    post "/orgs/:organization/members/:name", OrganizationUserController, :update
    delete "/orgs/:organization/members/:name", OrganizationUserController, :delete

    get "/repos", RepositoryController, :index
    get "/repos/:repository", RepositoryController, :show

    for prefix <- ["/", "/repos/:repository"] do
      scope prefix do
        get "/packages", PackageController, :index
        get "/packages/:name", PackageController, :show
        get "/packages/:name/audit-logs", PackageController, :audit_logs

        get "/packages/:name/releases/:version", ReleaseController, :show
        delete "/packages/:name/releases/:version", ReleaseController, :delete

        post "/packages/:name/releases/:version/retire", RetirementController, :create
        delete "/packages/:name/releases/:version/retire", RetirementController, :delete

        get "/packages/:name/releases/:version/docs", DocsController, :show
        delete "/packages/:name/releases/:version/docs", DocsController, :delete

        get "/packages/:name/owners", OwnerController, :index
        get "/packages/:name/owners/:username", OwnerController, :show
        put "/packages/:name/owners/:username", OwnerController, :create
        delete "/packages/:name/owners/:username", OwnerController, :delete
      end
    end

    for prefix <- ["/", "/orgs/:organization"] do
      scope prefix do
        get "/keys", KeyController, :index
        get "/keys/:name", KeyController, :show
        post "/keys", KeyController, :create
        delete "/keys", KeyController, :delete_all
        delete "/keys/:name", KeyController, :delete
      end
    end

    post "/short_url", ShortURLController, :create
    get "/auth", AuthController, :show
  end

  if Mix.env() in [:dev, :test, :hex] do
    scope "/repo", HexpmWeb do
      get "/names", TestController, :names
      get "/versions", TestController, :versions
      get "/installs/hex-1.x.csv", TestController, :installs_csv

      for prefix <- ["/", "/repos/:repository"] do
        scope prefix do
          get "/packages/:package", TestController, :package
          get "/tarballs/:ball", TestController, :tarball
        end
      end
    end

    scope "/api", HexpmWeb do
      pipe_through :api

      post "/repo", TestController, :repo
    end
  end

  scope "/" do
    pipe_through [:browser, :admin]
    live_dashboard("/db", metrics: HexpmWeb.Telemetry)
  end

  def user_path(%User{organization: nil} = user) do
    ~p"/users/#{user}"
  end

  def user_path(%User{organization: %Organization{} = organization}) do
    ~p"/orgs/#{organization}"
  end
end
