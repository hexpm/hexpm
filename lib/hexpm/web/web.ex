defmodule Hexpm.Web do
  @moduledoc """
  A module that keeps using definitions for controllers,
  views and so on.

  This can be used in your application as:

      use Hexpm.Web, :controller
      use Hexpm.Web, :view

  The definitions below will be executed for every view,
  controller, etc, so keep them short and clean, focused
  on imports, uses and aliases.

  Do NOT define functions inside the quoted expressions
  below.
  """

  def schema do
    quote do
      use Ecto.Schema

      import Ecto
      import Ecto.Changeset
      import Ecto.Query, only: [from: 1, from: 2]
      import Hexpm.Validation

      alias Ecto.Multi

      Hexpm.Web.shared
    end
  end

  def context do
    quote do
      import Ecto
      import Ecto.Changeset
      import Ecto.Query, only: [from: 1, from: 2]
      import Hexpm.Accounts.AuditLog, only: [audit: 4, audit_many: 4, audit_with_user: 4]

      alias Hexpm.Repo
      alias Ecto.Multi

      alias Hexpm.Emails
      alias Hexpm.Emails.Mailer

      Hexpm.Web.shared
    end
  end

  def controller do
    quote do
      use Phoenix.Controller, namespace: Hexpm.Web

      import Ecto
      import Ecto.Query, only: [from: 1, from: 2]

      import Hexpm.Web.{Router.Helpers, ControllerHelpers, AuthHelpers}

      alias Hexpm.Web.Endpoint

      Hexpm.Web.shared
    end
  end

  def view do
    quote do
      use Phoenix.View, root: "lib/hexpm/web/templates",
                        namespace: Hexpm.Web
      use Phoenix.HTML

      # Import convenience functions from controllers
      import Phoenix.Controller, only: [get_csrf_token: 0, get_flash: 2, view_module: 1]

      # Use all HTML functionality (forms, tags, etc)
      import Phoenix.HTML.Form, except: [
        text_input: 2, text_input: 3,
        email_input: 2, email_input: 3,
        password_input: 2, password_input: 3,
        select: 3, select: 4
      ]

      import Hexpm.Web.{Router.Helpers, ViewHelpers, ViewIcons}

      alias Hexpm.Web.Endpoint

      Hexpm.Web.shared
    end
  end

  def router do
    quote do
      use Phoenix.Router
      import Hexpm.Web.Plugs
    end
  end

  defmacro shared do
    quote do
      alias Hexpm.{
        Accounts.AuditLog,
        Accounts.Auth,
        Accounts.Email,
        Accounts.Key,
        Accounts.Keys,
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
        Repository.Repositories,
        Repository.Repository,
        Repository.RepositoryUser,
        Repository.Requirement,
        Repository.Resolver,
        Repository.Sitemaps,
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
