defmodule Hexpm.Factory do
  use ExMachina.Ecto, repo: Hexpm.Repo
  alias Hexpm.Fake

  def user_factory() do
    %Hexpm.Accounts.User{
      username: Fake.sequence(:username),
      full_name: Fake.random(:full_name),
      emails: [build(:email)]
    }
  end

  def email_factory() do
    %Hexpm.Accounts.Email{
      email: Fake.sequence(:email),
      verified: true,
      primary: true,
      public: true
    }
  end

  def key_factory() do
    {user_secret, first, second} = Hexpm.Accounts.Key.gen_key()

    %Hexpm.Accounts.Key{
      name: Fake.random(:username),
      secret_first: first,
      secret_second: second,
      user_secret: user_secret
    }
  end

  def user_handles_factory() do
    %Hexpm.Accounts.UserHandles{}
  end

  def package_factory() do
    %Hexpm.Repository.Package{
      name: Fake.sequence(:package),
      meta: build(:package_metadata)
    }
  end

  def package_metadata_factory() do
    %Hexpm.Repository.PackageMetadata{
      description: Fake.random(:sentence),
      licenses: ["MIT"]
    }
  end

  def release_factory() do
    %Hexpm.Repository.Release{
      version: "1.0.0",
      checksum: "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
      meta: build(:release_metadata)
    }
  end

  def release_metadata_factory() do
    %Hexpm.Repository.ReleaseMetadata{
      app: Fake.random(:package),
      build_tools: ["mix"]
    }
  end
end
