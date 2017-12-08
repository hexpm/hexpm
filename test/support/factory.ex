defmodule Hexpm.Factory do
  use ExMachina.Ecto, repo: Hexpm.Repo
  alias Hexpm.Fake

  @password Bcrypt.hash_pwd_salt("password")

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
      name: Fake.random(:username),
      secret_first: first,
      secret_second: second,
      user_secret: user_secret,
      permissions: [build(:key_permission, domain: "api")]
    }
  end

  def key_permission_factory() do
    %Hexpm.Accounts.KeyPermission{}
  end

  def user_handles_factory() do
    %Hexpm.Accounts.UserHandles{}
  end

  def repository_factory() do
    %Hexpm.Repository.Repository{
      name: Fake.sequence(:package),
      public: false,
      active: true,
      billing_active: true
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

  def repository_user_factory() do
    %Hexpm.Repository.RepositoryUser{
      role: "read"
    }
  end

  def release_factory() do
    %Hexpm.Repository.Release{
      version: "1.0.0",
      checksum: "E3B0C44298FC1C149AFBF4C8996FB92427AE41E4649B934CA495991B7852B855",
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
end
