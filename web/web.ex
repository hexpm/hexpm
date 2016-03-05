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

      HexWeb.Web.shared
    end
  end

  def controller do
    quote do
      use Phoenix.Controller

      alias HexWeb.Repo
      import Ecto
      import Ecto.Query, only: [from: 1, from: 2]

      import HexWeb.Router.Helpers
      import HexWeb.ControllerHelpers
      import HexWeb.AuthHelpers

      HexWeb.Web.shared
    end
  end

  def view do
    quote do
      use Phoenix.View, root: "web/templates"

      # Import convenience functions from controllers
      import Phoenix.Controller, only: [get_csrf_token: 0, get_flash: 2, view_module: 1]

      # Use all HTML functionality (forms, tags, etc)
      use Phoenix.HTML

      import HexWeb.Router.Helpers
      import HexWeb.ViewHelpers

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
        Download,
        Install,
        Key,
        Package,
        PackageDownload,
        PackageMetadata,
        PackageOwner,
        Registry,
        Release,
        ReleaseDownload,
        ReleaseMetadata,
        Requirement,
        User
      }

      import HexWeb.SharedHelpers
    end
  end

  @doc """
  When used, dispatch to the appropriate controller/view/etc.
  """
  defmacro __using__(which) when is_atom(which) do
    apply(__MODULE__, which, [])
  end
end
