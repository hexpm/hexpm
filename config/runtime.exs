import Config

default_sso_mode = if config_env() == :dev, do: "enabled", else: "off"

sso_mode =
  case System.get_env("HEXPM_SSO_MODE", default_sso_mode) do
    "off" -> :off
    "beta" -> :beta
    "enabled" -> :enabled
    value -> raise "invalid HEXPM_SSO_MODE #{inspect(value)}; expected off, beta, or enabled"
  end

sso_beta_organizations =
  System.get_env("HEXPM_SSO_BETA_ORGANIZATIONS", "")
  |> String.split(",", trim: true)
  |> Enum.map(&String.trim/1)
  |> Enum.reject(&(&1 == ""))
  |> Enum.uniq()

sso_exempt_issuer_hosts =
  if config_env() == :prod do
    []
  else
    System.get_env("HEXPM_SSO_EXEMPT_ISSUER_HOSTS", "")
    |> String.split(",", trim: true)
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.uniq()
  end

config :hexpm, sso_exempt_issuer_hosts: sso_exempt_issuer_hosts

config :hexpm, :organization_sso,
  mode: sso_mode,
  beta_organizations: sso_beta_organizations

if config_env() == :prod do
  mode =
    case System.get_env("HEXPM_MODE") do
      value when value in [nil, "", "web"] -> :web
      "worker" -> :worker
      value -> raise "invalid HEXPM_MODE #{inspect(value)}; expected \"web\" or \"worker\""
    end

  config :hexpm,
    secret: System.fetch_env!("HEXPM_SECRET"),
    private_key: System.fetch_env!("HEXPM_SIGNING_KEY"),
    repo_bucket: System.fetch_env!("HEXPM_REPO_BUCKET"),
    logs_bucket: System.fetch_env!("HEXPM_LOGS_BUCKET"),
    # Staging serves no package downloads, so an empty day is not a broken
    # log pipeline there
    stats_expect_downloads: System.fetch_env!("HEXPM_ENV") == "prod",
    audit_bucket: System.fetch_env!("HEXPM_AUDIT_BUCKET"),
    docs_bucket: System.fetch_env!("HEXPM_DOCS_BUCKET"),
    preview_bucket: System.fetch_env!("HEXPM_PREVIEW_BUCKET"),
    diff_bucket: System.fetch_env!("HEXPM_DIFF_BUCKET"),
    diff_cache_version: System.fetch_env!("HEXPM_DIFF_CACHE_VERSION") |> String.to_integer(),
    cdn_url: System.fetch_env!("HEXPM_CDN_URL"),
    docs_url: System.fetch_env!("HEXPM_DOCS_URL"),
    private_docs_url: System.fetch_env!("HEXPM_PRIVATE_DOCS_URL"),
    fastly_key: System.fetch_env!("HEXPM_FASTLY_KEY"),
    fastly_hexrepo: System.fetch_env!("HEXPM_FASTLY_HEXREPO"),
    jwt_signing_key: System.fetch_env!("HEXPM_JWT_SIGNING_KEY"),
    billing_key: System.fetch_env!("HEXPM_BILLING_KEY"),
    billing_url: System.fetch_env!("HEXPM_BILLING_URL"),
    host: System.fetch_env!("HEXPM_HOST"),
    dashboard_user: System.fetch_env!("HEXPM_DASHBOARD_USER"),
    dashboard_password: System.fetch_env!("HEXPM_DASHBOARD_PASSWORD"),
    img_url: System.fetch_env!("HEXPM_IMG_URL"),
    img_proxy_secret: System.fetch_env!("HEXPM_IMG_PROXY_SECRET"),
    readme_host: System.fetch_env!("HEXPM_README_HOST"),
    readme_url: System.fetch_env!("HEXPM_README_URL"),
    secret_scan_notify: System.get_env("HEXPM_SECRET_SCAN_NOTIFY") == "true"

  config :hexpm, :varsel,
    report_url: System.fetch_env!("HEXPM_VARSEL_REPORT_URL"),
    audience: System.fetch_env!("HEXPM_VARSEL_JWT_AUDIENCE"),
    signing_key: System.fetch_env!("HEXPM_VARSEL_SIGNING_KEY"),
    key_id: System.fetch_env!("HEXPM_VARSEL_KEY_ID")

  config :hexpm, :hcaptcha,
    sitekey: System.fetch_env!("HEXPM_HCAPTCHA_SITEKEY"),
    secret: System.fetch_env!("HEXPM_HCAPTCHA_SECRET")

  config :ueberauth, Ueberauth.Strategy.Github.OAuth,
    client_id: System.fetch_env!("HEXPM_GITHUB_CLIENT_ID"),
    client_secret: System.fetch_env!("HEXPM_GITHUB_CLIENT_SECRET")

  config :ex_aws,
    access_key_id: System.fetch_env!("HEXPM_AWS_ACCESS_KEY_ID"),
    secret_access_key: System.fetch_env!("HEXPM_AWS_ACCESS_KEY_SECRET")

  # GIT_SHA is baked into the image (see the Dockerfile) and matches the
  # release CI creates in Sentry, so issues resolved via commits auto-resolve
  # when the deploy carrying the fix is registered.
  sentry_release =
    case System.get_env("GIT_SHA") do
      sha when sha in [nil, "", "unknown"] -> nil
      sha -> sha
    end

  config :sentry,
    dsn: System.fetch_env!("HEXPM_SENTRY_DSN"),
    environment_name: System.fetch_env!("HEXPM_ENV"),
    release: sentry_release

  config :hexpm,
    email_base_url: "https://#{System.fetch_env!("HEXPM_HOST")}",
    email_host: System.fetch_env!("HEXPM_EMAIL_HOST"),
    levenshtein_threshold: System.fetch_env!("HEXPM_LEVENSHTEIN_THRESHOLD")

  config :hexpm, Hexpm.Emails.Mailer, api_key: System.fetch_env!("HEXPM_SENDGRID_API_KEY")

  # IP geolocation database for audit-log locations. Resolution order:
  #
  #   1. HEXPM_GEOIP_COUNTRY_PATH, if set.
  #   2. priv/geoip/country.mmdb, which the Docker image bakes in at build time
  #      (mix download_geoip) — so the official image works with zero config.
  #
  # Fail-soft: if no database is found, geolix logs an info message and returns
  # nil for all lookups; the app boots normally and location fields are simply
  # omitted until a database is provisioned.
  default_geoip_path =
    case :code.priv_dir(:hexpm) do
      {:error, _} -> nil
      priv_dir -> Path.join(to_string(priv_dir), "geoip/country.mmdb")
    end

  geoip_country_path = System.get_env("HEXPM_GEOIP_COUNTRY_PATH") || default_geoip_path

  if geoip_country_path do
    config :geolix,
      databases: [
        %{
          id: :country,
          adapter: Geolix.Adapter.MMDB2,
          source: geoip_country_path
        }
      ]
  end

  # Set on both web and worker deployments so Prometheus can scrape all pods
  if metrics_port = System.get_env("HEXPM_METRICS_PORT") do
    config :hexpm, metrics_port: String.to_integer(metrics_port)
  end

  # Only the web server's own wiring may live in this block: everything else is
  # shared, because Oban jobs read app config on worker pods too. The env vars
  # below (HEXPM_PORT, HEXPM_SECRET_KEY_BASE, BEAM_PORT, ...) are the ones the
  # worker deployment does not have to provide.
  if mode == :web do
    config :hexpm, Oban, queues: false, plugins: false, peer: false

    hexpm_port =
      case System.get_env("HEXPM_PORT") do
        port when port not in [nil, ""] -> String.to_integer(port)
        _ -> nil
      end

    endpoint_config = [
      url: [host: System.fetch_env!("HEXPM_HOST")],
      secret_key_base: System.fetch_env!("HEXPM_SECRET_KEY_BASE"),
      live_view: [signing_salt: System.fetch_env!("HEXPM_LIVE_VIEW_SIGNING_SALT")],
      check_origin: ["//#{System.fetch_env!("HEXPM_HOST")}"]
    ]

    endpoint_config =
      if hexpm_port do
        [{:http, [port: hexpm_port]} | endpoint_config]
      else
        [{:server, false} | endpoint_config]
      end

    config :hexpm, HexpmWeb.Endpoint, endpoint_config

    config :kernel,
      inet_dist_listen_min: String.to_integer(System.fetch_env!("BEAM_PORT")),
      inet_dist_listen_max: String.to_integer(System.fetch_env!("BEAM_PORT"))
  end

  if mode == :worker do
    config :hexpm, Oban,
      queues: [
        periodic: String.to_integer(System.fetch_env!("HEXPM_OBAN_PERIODIC_CONCURRENCY")),
        heavy: String.to_integer(System.fetch_env!("HEXPM_OBAN_HEAVY_CONCURRENCY")),
        registry: String.to_integer(System.fetch_env!("HEXPM_OBAN_REGISTRY_CONCURRENCY")),
        purge: String.to_integer(System.fetch_env!("HEXPM_OBAN_PURGE_CONCURRENCY")),
        email: String.to_integer(System.fetch_env!("HEXPM_OBAN_EMAIL_CONCURRENCY"))
      ]

    config :hexpm,
      docs_private_bucket: "gcs," <> System.fetch_env!("HEXPM_DOCS_PRIVATE_BUCKET"),
      preview_queue_id: System.fetch_env!("HEXPM_PREVIEW_QUEUE_ID"),
      hexdocs_queue_id: System.fetch_env!("HEXPM_DOCS_QUEUE_ID"),
      hexdocs_typesense_url: System.fetch_env!("HEXPM_DOCS_TYPESENSE_URL"),
      hexdocs_typesense_api_key: System.fetch_env!("HEXPM_DOCS_TYPESENSE_API_KEY"),
      hexdocs_typesense_collection: System.fetch_env!("HEXPM_DOCS_TYPESENSE_COLLECTION"),
      hexdocs_github_user: System.fetch_env!("HEXPM_DOCS_GITHUB_USER"),
      hexdocs_github_token: System.fetch_env!("HEXPM_DOCS_GITHUB_TOKEN"),
      fastly_docs_key: System.fetch_env!("HEXPM_FASTLY_DOCS_KEY"),
      fastly_hexdocs: System.fetch_env!("HEXPM_FASTLY_DOCS"),
      fastly_hexdocs_private: System.fetch_env!("HEXPM_FASTLY_PRIVATE_DOCS")
  end
end
