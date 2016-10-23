defmodule HexWeb.Web do
  @moduledoc """
  A module that keeps using definitions for controllers,
  views and so on.

  This can be used in your application as:

      use HexWeb.Web, :controller
      use HexWeb.Web, :view

  The definitions below will be executed for every view,
  controller, etc, so keep them short and clean, focused
  on imports, uses and aliases.

  Do NOT define functions inside the quoted expressions
  below.
  """

  def model do
    quote do
      use Ecto.Schema

      import Ecto
      import Ecto.Changeset
      import Ecto.Query, only: [from: 1, from: 2]
      import HexWeb.Validation

      alias Ecto.Multi

      HexWeb.Web.shared
    end
  end

  def crud do
    quote do
      import Ecto
      import Ecto.Changeset
      import Ecto.Query, only: [from: 1, from: 2]
      import HexWeb.AuditLog, only: [audit: 4, audit_many: 4, audit_with_user: 4]

      alias HexWeb.Repo
      alias Ecto.Multi

      HexWeb.Web.shared
    end
  end

  def controller do
    quote do
      use Phoenix.Controller

      import Ecto
      import Ecto.Query, only: [from: 1, from: 2]

      import HexWeb.{Router.Helpers, ControllerHelpers, AuthHelpers}

      alias HexWeb.Endpoint

      HexWeb.Web.shared
    end
  end

  def view do
    quote do
      use Phoenix.View, root: "web/templates"
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

      import HexWeb.{Router.Helpers, ViewHelpers, ViewIcons}

      alias HexWeb.Endpoint

      HexWeb.Web.shared
    end
  end

  def router do
    quote do
      use Phoenix.Router
      import HexWeb.Plugs
    end
  end

  defmacro shared do
    quote do
      alias HexWeb.{
        Assets,
        AuditLog,
        Download,
        Email,
        Install,
        Installs,
        Key,
        Keys,
        Mailer,
        Owners,
        Package,
        Packages,
        PackageDownload,
        PackageMetadata,
        PackageOwner,
        RegistryBuilder,
        Release,
        Releases,
        ReleaseDownload,
        ReleaseMetadata,
        Requirement,
        Sitemaps,
        User,
        Users,
        UserHandles,
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
