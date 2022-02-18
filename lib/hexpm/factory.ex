defmodule Hexpm.Factory do
  use ExMachina.Ecto, repo: Hexpm.Repo
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
    %Hexpm.Repository.PackageOwner{}
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
      app_enabled: true,
      tfa_enabled: true,
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
end
