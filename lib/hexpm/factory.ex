defmodule Hexpm.Factory do
  use ExMachina.Ecto, repo: Hexpm.Repo
  use Hexpm.Factory.ReleaseWithTarballStrategy, repo: Hexpm.Repo
  alias Hexpm.Fake

  @password Bcrypt.hash_pwd_salt("password")
  @checksum "E3B0C44298FC1C149AFBF4C8996FB92427AE41E4649B934CA495991B7852B855"

  def user_factory() do
    %Hexpm.Accounts.User{
      username: Fake.sequence(:username),
      password: @password,
      full_name: Fake.random(:full_name),
      emails: [build(:email)]
    }
  end

  def email_factory() do
    %Hexpm.Accounts.Email{
      email: Fake.sequence(:email),
      verified: true,
      primary: true,
      public: true,
      gravatar: true
    }
  end

  def user_provider_factory() do
    %Hexpm.Accounts.UserProvider{
      provider: "github",
      provider_uid: "#{:rand.uniform(1_000_000)}",
      provider_email: Fake.sequence(:email),
      provider_data: %{
        "login" => Fake.random(:username),
        "name" => Fake.random(:full_name)
      }
    }
  end

  def user_with_github_factory() do
    user = build(:user, password: nil)
    user_provider = build(:user_provider, user: user)
    %{user | user_providers: [user_provider]}
  end

  def key_factory() do
    {user_secret, first, second} = Hexpm.Accounts.Key.gen_key()

    %Hexpm.Accounts.Key{
      name: "#{Fake.random(:username)}-#{:erlang.unique_integer()}",
      secret_first: first,
      secret_second: second,
      user_secret: user_secret,
      permissions: [build(:key_permission, domain: "api")],
      user: nil,
      organization: nil
    }
  end

  def key_permission_factory() do
    %Hexpm.Accounts.KeyPermission{}
  end

  def user_handles_factory() do
    %Hexpm.Accounts.UserHandles{}
  end

  def organization_factory() do
    name = Fake.sequence(:package)

    %Hexpm.Accounts.Organization{
      name: name,
      user: build(:user, username: name),
      billing_active: true,
      trial_end: ~U[2020-01-01T00:00:00Z]
    }
  end

  def audit_log_factory() do
    %Hexpm.Accounts.AuditLog{
      action: "",
      params: %{}
    }
  end

  def repository_factory() do
    name = Fake.sequence(:package)

    %Hexpm.Repository.Repository{
      name: name,
      organization: build(:organization, name: name, user: build(:user, username: name))
    }
  end

  def package_factory() do
    %Hexpm.Repository.Package{
      name: Fake.sequence(:package),
      meta: build(:package_metadata),
      repository_id: 1
    }
  end

  def package_metadata_factory() do
    %Hexpm.Repository.PackageMetadata{
      description: Fake.random(:sentence),
      licenses: ["MIT"]
    }
  end

  def package_owner_factory() do
    %Hexpm.Repository.PackageOwner{level: "full"}
  end

  def package_report_factory() do
    %Hexpm.Repository.PackageReport{}
  end

  def package_report_release_factory() do
    %Hexpm.Repository.PackageReportRelease{}
  end

  def organization_user_factory() do
    %Hexpm.Accounts.OrganizationUser{
      role: "read"
    }
  end

  def organization_sso_connection_factory() do
    %Hexpm.Accounts.SSO.Connection{
      issuer: "https://identity.example.com/oauth2/default",
      client_id: "client-id",
      client_secret: "client-secret",
      discovery_document: %{},
      jwks_document: %{"keys" => []},
      discovery_expires_at: DateTime.add(DateTime.utc_now(), 3_600, :second),
      jwks_expires_at: DateTime.add(DateTime.utc_now(), 3_600, :second),
      metadata_expires_at: DateTime.add(DateTime.utc_now(), 3_600, :second)
    }
  end

  def organization_sso_identity_factory() do
    %Hexpm.Accounts.SSO.Identity{
      issuer: "https://identity.example.com/oauth2/default",
      subject: "00u123",
      provider_email: Fake.sequence(:email)
    }
  end

  def email_outbox_entry_factory() do
    %Hexpm.Emails.OutboxEntry{
      category: "test.email",
      ordering_key: "test:#{Fake.sequence(:word)}",
      email: %{
        "version" => 1,
        "subject" => "Test email",
        "from" => %{"name" => "Hex.pm", "address" => "noreply@hex.pm"},
        "to" => [%{"name" => "", "address" => Fake.sequence(:email)}],
        "cc" => [],
        "bcc" => [],
        "reply_to" => nil,
        "text_body" => "Test email",
        "html_body" => "<p>Test email</p>",
        "headers" => %{},
        "provider_options" => %{}
      }
    }
  end

  def release_factory() do
    %Hexpm.Repository.Release{
      version: "1.0.0",
      inner_checksum: Base.decode16!(@checksum),
      outer_checksum: Base.decode16!(@checksum),
      meta: build(:release_metadata)
    }
  end

  def release_metadata_factory() do
    %Hexpm.Repository.ReleaseMetadata{
      app: Fake.random(:package),
      build_tools: ["mix"]
    }
  end

  def requirement_factory() do
    %Hexpm.Repository.Requirement{
      app: Fake.random(:package),
      optional: false
    }
  end

  def download_factory() do
    %Hexpm.Repository.Download{
      day: ~D[2017-01-01]
    }
  end

  def install_factory() do
    %Hexpm.Repository.Install{}
  end

  def block_address_factory() do
    %Hexpm.BlockAddress.Entry{
      comment: "blocked"
    }
  end

  def short_url_factory() do
    %Hexpm.ShortURLs.ShortURL{
      url: "",
      short_code: ""
    }
  end

  def user_with_tfa_factory() do
    %Hexpm.Accounts.User{
      username: Fake.sequence(:username),
      password: @password,
      full_name: Fake.random(:full_name),
      emails: [build(:email)],
      tfa: build(:tfa)
    }
  end

  def tfa_factory() do
    %Hexpm.Accounts.TFA{
      secret: "OZIH4PZP53MCYZ6Z",
      recovery_codes: [
        %{
          id: Ecto.UUID.generate(),
          code: "1234-1234-1234-1234",
          used_at: nil
        },
        %{
          id: Ecto.UUID.generate(),
          code: "4321-4321-4321-4321",
          used_at: ~U[2020-01-01 00:00:00Z]
        }
      ]
    }
  end

  def oauth_client_factory() do
    %Hexpm.OAuth.Client{
      client_id: Hexpm.OAuth.Clients.generate_client_id(),
      name: "Test OAuth Client",
      client_type: "public",
      allowed_grant_types: [
        "authorization_code",
        "urn:ietf:params:oauth:grant-type:device_code",
        "refresh_token",
        "client_credentials"
      ],
      allowed_scopes: ["api", "api:read", "api:write", "repositories"],
      redirect_uris: ["https://example.com/callback"]
    }
  end

  def oauth_token_factory() do
    expires_at = DateTime.add(DateTime.utc_now(), 30 * 24 * 3600, :second)
    refresh_token_expires_at = DateTime.add(DateTime.utc_now(), 30 * 24 * 3600, :second)

    %Hexpm.OAuth.Token{
      jti: "test-jti-#{:erlang.unique_integer()}",
      token_type: "bearer",
      scopes: ["api"],
      expires_at: expires_at,
      refresh_token_expires_at: refresh_token_expires_at,
      grant_type: "authorization_code",
      client_id: Hexpm.OAuth.Clients.generate_client_id()
    }
  end

  def session_factory() do
    user = build(:user)

    %Hexpm.UserSession{
      type: "browser",
      name: "Test Browser Session",
      session_token: :crypto.strong_rand_bytes(32),
      user_id: user.id
    }
  end

  def oauth_session_factory() do
    user = build(:user)

    %Hexpm.UserSession{
      type: "oauth",
      name: "Test OAuth Session",
      client_id: Hexpm.OAuth.Clients.generate_client_id(),
      user_id: user.id
    }
  end

  def advisory_affected_version_factory() do
    %Hexpm.Security.AdvisoryAffectedVersion{
      requirement: Version.parse_requirement!(">= 0.0.0")
    }
  end

  def advisory_reference_factory() do
    %Hexpm.Security.AdvisoryReference{
      type: "WEB",
      url: "https://example.com/advisory"
    }
  end

  def security_advisories_factory() do
    %Hexpm.Security.Advisory{
      id: "GHSA-mj35-2rgf-cv8p",
      summary:
        "OpenID Connect client Atom Exhaustion in provider configuration worker ets table location",
      aliases: ["CVE-2024-31209"],
      published_at: ~U[2024-04-03 16:46:30Z],
      modified_at: ~U[2024-04-05 01:28:39Z],
      cvss_vector: "CVSS:3.1/AV:L/AC:H/PR:H/UI:N/S:C/C:N/I:N/A:H",
      cvss_score: 5.5,
      cvss_rating: "medium",
      references: [
        %Hexpm.Security.AdvisoryReference{
          type: "WEB",
          url: "https://github.com/erlef/oidcc/security/advisories/GHSA-mj35-2rgf-cv8p"
        }
      ]
    }
  end
end
