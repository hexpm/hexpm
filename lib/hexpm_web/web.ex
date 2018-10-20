defmodule HexpmWeb do
  @moduledoc """
  A module that keeps using definitions for controllers,
  views and so on.

  This can be used in your application as:

      use HexpmWeb, :controller
      use HexpmWeb, :view

  The definitions below will be executed for every view,
  controller, etc, so keep them short and clean, focused
  on imports, uses and aliases.

  Do NOT define functions inside the quoted expressions
  below.
  """

  def schema() do
    quote do
      use Ecto.Schema
      @timestamps_opts [type: :utc_datetime_usec]

      import Ecto
      import Ecto.Changeset
      import Ecto.Query, only: [from: 1, from: 2]
      import Hexpm.Changeset

      alias Ecto.Multi

      HexpmWeb.shared()
    end
  end

  def context() do
    quote do
      import Ecto
      import Ecto.Changeset
      import Ecto.Query, only: [from: 1, from: 2]
      import Hexpm.Accounts.AuditLog, only: [audit: 4, audit_many: 4, audit_with_user: 4]

      alias Ecto.Multi

      alias Hexpm.{Emails, Emails.Mailer, Repo}

      HexpmWeb.shared()
    end
  end

  def controller() do
    quote do
      use Phoenix.Controller, namespace: HexpmWeb

      import Ecto
      import Ecto.Query, only: [from: 1, from: 2]

      import HexpmWeb.{ControllerHelpers, AuthHelpers}

      alias HexpmWeb.Endpoint
      alias HexpmWeb.Router.Helpers, as: Routes

      HexpmWeb.shared()
    end
  end

  def view() do
    quote do
      use Phoenix.View,
        root: "lib/hexpm_web/templates",
        namespace: HexpmWeb

      use Phoenix.HTML

      # Import convenience functions from controllers
      import Phoenix.Controller, only: [get_csrf_token: 0, get_flash: 2, view_module: 1]

      # Use all HTML functionality (forms, tags, etc)
      import Phoenix.HTML.Form,
        except: [
          text_input: 2,
          text_input: 3,
          email_input: 2,
          email_input: 3,
          password_input: 2,
          password_input: 3,
          select: 3,
          select: 4
        ]

      import HexpmWeb.{ViewHelpers, ViewIcons}

      alias HexpmWeb.Endpoint
      alias HexpmWeb.Router.Helpers, as: Routes

      HexpmWeb.shared()
    end
  end

  def router() do
    quote do
      use Phoenix.Router
      import HexpmWeb.Plugs
    end
  end

  defmacro shared do
    quote do
      alias Hexpm.{
        Accounts.AuditLog,
        Accounts.Auth,
        Accounts.Email,
        Accounts.Key,
        Accounts.KeyPermission,
        Accounts.Keys,
        Accounts.Organization,
        Accounts.Organizations,
        Accounts.OrganizationUser,
        Accounts.PasswordReset,
        Accounts.Session,
        Accounts.User,
        Accounts.UserHandles,
        Accounts.Users,
        Emails,
        Emails.Mailer,
        Repository.Assets,
        Repository.Download,
        Repository.Install,
        Repository.Installs,
        Repository.Owners,
        Repository.Package,
        Repository.PackageDownload,
        Repository.PackageMetadata,
        Repository.PackageOwner,
        Repository.Packages,
        Repository.RegistryBuilder,
        Repository.Release,
        Repository.ReleaseDownload,
        Repository.ReleaseMetadata,
        Repository.ReleaseRetirement,
        Repository.Releases,
        Repository.Repository,
        Repository.Requirement,
        Repository.Resolver,
        Repository.Sitemaps
      }
    end
  end

  @doc """
  When used, dispatch to the appropriate controller/view/etc.
  """
  defmacro __using__(which) when is_atom(which) do
    apply(__MODULE__, which, [])
  end
end
