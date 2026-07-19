import Config

if config_env() == :prod do
  mode =
    case System.get_env("HEXPM_MODE") do
      value when value in [nil, "", "web"] -> :web
      "worker" -> :worker
      value -> raise "invalid HEXPM_MODE #{inspect(value)}; expected \"web\" or \"worker\""
    end

  config :hexpm,
    private_key: System.fetch_env!("HEXPM_SIGNING_KEY"),
    repo_bucket: System.fetch_env!("HEXPM_REPO_BUCKET"),
    logs_bucket: System.fetch_env!("HEXPM_LOGS_BUCKET"),
    docs_bucket: System.fetch_env!("HEXPM_DOCS_BUCKET"),
    preview_bucket: System.fetch_env!("HEXPM_PREVIEW_BUCKET"),
    diff_bucket: System.fetch_env!("HEXPM_DIFF_BUCKET"),
    diff_cache_version: System.fetch_env!("HEXPM_DIFF_CACHE_VERSION") |> String.to_integer(),
    cdn_url: System.fetch_env!("HEXPM_CDN_URL"),
    docs_url: System.fetch_env!("HEXPM_DOCS_URL"),
    private_docs_url: System.fetch_env!("HEXPM_PRIVATE_DOCS_URL"),
    fastly_key: System.fetch_env!("HEXPM_FASTLY_KEY"),
    fastly_hexrepo: System.fetch_env!("HEXPM_FASTLY_HEXREPO"),
    billing_key: System.fetch_env!("HEXPM_BILLING_KEY"),
    billing_url: System.fetch_env!("HEXPM_BILLING_URL")

  config :ex_aws,
    access_key_id: System.fetch_env!("HEXPM_AWS_ACCESS_KEY_ID"),
    secret_access_key: System.fetch_env!("HEXPM_AWS_ACCESS_KEY_SECRET")

  config :sentry,
    dsn: System.fetch_env!("HEXPM_SENTRY_DSN"),
    environment_name: System.fetch_env!("HEXPM_ENV")

  if mode == :web do
    config :hexpm, Oban, queues: false, plugins: false, peer: false

    config :hexpm,
      host: System.fetch_env!("HEXPM_HOST"),
      secret: System.fetch_env!("HEXPM_SECRET"),
      email_host: System.fetch_env!("HEXPM_EMAIL_HOST"),
      levenshtein_threshold: System.fetch_env!("HEXPM_LEVENSHTEIN_THRESHOLD"),
      dashboard_user: System.fetch_env!("HEXPM_DASHBOARD_USER"),
      dashboard_password: System.fetch_env!("HEXPM_DASHBOARD_PASSWORD"),
      jwt_signing_key: System.fetch_env!("HEXPM_JWT_SIGNING_KEY"),
      img_url: System.fetch_env!("HEXPM_IMG_URL"),
      img_proxy_secret: System.fetch_env!("HEXPM_IMG_PROXY_SECRET"),
      readme_host: System.fetch_env!("HEXPM_README_HOST"),
      readme_url: System.fetch_env!("HEXPM_README_URL")

    config :hexpm, Hexpm.Emails.Mailer, api_key: System.fetch_env!("HEXPM_SENDGRID_API_KEY")

    config :hexpm, :hcaptcha,
      sitekey: System.fetch_env!("HEXPM_HCAPTCHA_SITEKEY"),
      secret: System.fetch_env!("HEXPM_HCAPTCHA_SECRET")

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

    config :ueberauth, Ueberauth.Strategy.Github.OAuth,
      client_id: System.fetch_env!("HEXPM_GITHUB_CLIENT_ID"),
      client_secret: System.fetch_env!("HEXPM_GITHUB_CLIENT_SECRET")
  end

  if mode == :worker do
    config :hexpm, Oban,
      queues: [
        periodic: String.to_integer(System.fetch_env!("HEXPM_OBAN_PERIODIC_CONCURRENCY")),
        heavy: String.to_integer(System.fetch_env!("HEXPM_OBAN_HEAVY_CONCURRENCY"))
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
