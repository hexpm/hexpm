defmodule Hexpm.RuntimeConfigTest do
  # Sync: reading runtime.exs goes through the VM-global process environment.
  use ExUnit.Case, async: false

  @shared_env %{
    "HEXPM_SECRET" => "app-secret",
    "HEXPM_SIGNING_KEY" => "signing-key",
    "HEXPM_REPO_BUCKET" => "s3,us-east-1,repo",
    "HEXPM_LOGS_BUCKET" => "gcs,logs",
    "HEXPM_DOCS_BUCKET" => "gcs,docs",
    "HEXPM_PREVIEW_BUCKET" => "gcs,preview",
    "HEXPM_DIFF_BUCKET" => "gcs,diff",
    "HEXPM_DIFF_CACHE_VERSION" => "1",
    "HEXPM_CDN_URL" => "https://repo.example.com",
    "HEXPM_DOCS_URL" => "https://docs.example.com",
    "HEXPM_PRIVATE_DOCS_URL" => "https://private-docs.example.com",
    "HEXPM_FASTLY_KEY" => "fastly-key",
    "HEXPM_FASTLY_HEXREPO" => "fastly-hexrepo",
    "HEXPM_JWT_SIGNING_KEY" => "jwt-signing-key",
    "HEXPM_BILLING_KEY" => "billing-key",
    "HEXPM_BILLING_URL" => "https://billing.example.com",
    "HEXPM_AWS_ACCESS_KEY_ID" => "aws-id",
    "HEXPM_AWS_ACCESS_KEY_SECRET" => "aws-secret",
    "HEXPM_SENTRY_DSN" => "https://sentry.example.com/1",
    "HEXPM_ENV" => "prod",
    "HEXPM_HOST" => "hex.example.com",
    "HEXPM_EMAIL_HOST" => "hex.example.com",
    "HEXPM_LEVENSHTEIN_THRESHOLD" => "2",
    "HEXPM_SENDGRID_API_KEY" => "sendgrid-key"
  }

  @worker_env Map.merge(@shared_env, %{
                "HEXPM_MODE" => "worker",
                "HEXPM_OBAN_PERIODIC_CONCURRENCY" => "5",
                "HEXPM_OBAN_HEAVY_CONCURRENCY" => "10",
                "HEXPM_OBAN_REGISTRY_CONCURRENCY" => "2",
                "HEXPM_OBAN_PURGE_CONCURRENCY" => "5",
                "HEXPM_DOCS_PRIVATE_BUCKET" => "docs-private",
                "HEXPM_PREVIEW_QUEUE_ID" => "preview-queue",
                "HEXPM_DOCS_QUEUE_ID" => "docs-queue",
                "HEXPM_DOCS_TYPESENSE_URL" => "https://typesense.example.com",
                "HEXPM_DOCS_TYPESENSE_API_KEY" => "typesense-key",
                "HEXPM_DOCS_TYPESENSE_COLLECTION" => "hexdocs",
                "HEXPM_DOCS_GITHUB_USER" => "docs-user",
                "HEXPM_DOCS_GITHUB_TOKEN" => "docs-token",
                "HEXPM_FASTLY_DOCS_KEY" => "fastly-docs-key",
                "HEXPM_FASTLY_DOCS" => "fastly-docs",
                "HEXPM_FASTLY_PRIVATE_DOCS" => "fastly-private-docs"
              })

  # The secret scan runs on worker pods only: web pods disable the Oban queues.
  # It fingerprints findings with the app secret, so worker mode has to set it.
  test "worker mode configures the secret scan" do
    config = read_runtime(@worker_env)

    assert config[:hexpm][:secret] == "app-secret"
    assert config[:hexpm][:secret_scan_notify] == false

    config = read_runtime(Map.put(@worker_env, "HEXPM_SECRET_SCAN_NOTIFY", "true"))

    assert config[:hexpm][:secret_scan_notify] == true
  end

  defp read_runtime(env) do
    previous = Map.new(env, fn {key, _value} -> {key, System.get_env(key)} end)

    on_exit(fn ->
      Enum.each(previous, fn
        {key, nil} -> System.delete_env(key)
        {key, value} -> System.put_env(key, value)
      end)
    end)

    System.put_env(env)
    Config.Reader.read!("config/runtime.exs", env: :prod)
  end
end
