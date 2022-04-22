import Config

if config_env() == :prod do
  config :hexpm,
    host: System.fetch_env!("HEXPM_HOST"),
    port: System.fetch_env!("HEXPM_PORT"),
    secret_key_base: System.fetch_env!("HEXPM_SECRET_KEY_BASE"),
    live_view_signing_salt: System.fetch_env!("HEXPM_LIVE_VIEW_SIGNING_SALT"),
    secret: System.fetch_env!("HEXPM_SECRET"),
    private_key: System.fetch_env!("HEXPM_SIGNING_KEY"),
    repo_bucket: System.fetch_env!("HEXPM_REPO_BUCKET"),
    logs_bucket: System.fetch_env!("HEXPM_LOGS_BUCKET"),
    docs_url: System.fetch_env!("HEXPM_DOCS_URL"),
    diff_url: System.fetch_env!("HEXPM_DIFF_URL"),
    preview_url: System.fetch_env!("HEXPM_PREVIEW_URL"),
    cdn_url: System.fetch_env!("HEXPM_CDN_URL"),
    email_host: System.fetch_env!("HEXPM_EMAIL_HOST"),
    fastly_key: System.fetch_env!("HEXPM_FASTLY_KEY"),
    fastly_hexrepo: System.fetch_env!("HEXPM_FASTLY_HEXREPO"),
    billing_key: System.fetch_env!("HEXPM_BILLING_KEY"),
    billing_url: System.fetch_env!("HEXPM_BILLING_URL"),
    levenshtein_threshold: System.fetch_env!("HEXPM_LEVENSHTEIN_THRESHOLD"),
    dashboard_user: System.fetch_env!("HEXPM_DASHBOARD_USER"),
    dashboard_password: System.fetch_env!("HEXPM_DASHBOARD_PASSWORD")

  config :hexpm, Hexpm.Emails.Mailer, api_key: System.fetch_env!("HEXPM_SENDGRID_API_KEY")

  config :ex_aws,
    access_key_id: System.fetch_env!("HEXPM_AWS_ACCESS_KEY_ID"),
    secret_access_key: System.fetch_env!("HEXPM_AWS_ACCESS_KEY_SECRET")

  config :rollbax,
    access_token: System.fetch_env!("HEXPM_ROLLBAR_ACCESS_TOKEN")

  config :kernel,
    inet_dist_listen_min: String.to_integer(System.fetch_env!("BEAM_PORT")),
    inet_dist_listen_max: String.to_integer(System.fetch_env!("BEAM_PORT"))
end
