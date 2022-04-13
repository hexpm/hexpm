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

  def controller() do
    quote do
      use Phoenix.Controller, namespace: HexpmWeb

      import Ecto
      import Ecto.Query, only: [from: 1, from: 2]

      import HexpmWeb.{ControllerHelpers, AuthHelpers}

      alias HexpmWeb.{Endpoint, Router}
      alias HexpmWeb.Router.Helpers, as: Routes

      use Hexpm.Shared
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

      import Phoenix.LiveView.Helpers

      import HexpmWeb.ViewIcons

      alias HexpmWeb.{Endpoint, Router, ViewHelpers}
      alias HexpmWeb.Router.Helpers, as: Routes

      use Hexpm.Shared
    end
  end

  def live_view do
    quote do
      use Phoenix.LiveView

      unquote(view_helpers())
    end
  end

  def live_component do
    quote do
      use Phoenix.LiveComponent

      unquote(view_helpers())
    end
  end

  def router() do
    quote do
      use Phoenix.Router
      import HexpmWeb.Plugs
      import Phoenix.LiveView.Router

      alias HexpmWeb.{Endpoint, Router}
      alias HexpmWeb.Router.Helpers, as: Routes
    end
  end

  defp view_helpers do
    quote do
      # Use all HTML functionality (forms, tags, etc)
      use Phoenix.HTML

      # Import LiveView helpers (live_render, live_component, live_patch, etc)
      import Phoenix.LiveView.Helpers

      # Import basic rendering functionality (render, render_layout, etc)
      import Phoenix.View

      alias HexpmWeb.Router.Helpers, as: Routes
    end
  end

  @doc """
  When used, dispatch to the appropriate controller/view/etc.
  """
  defmacro __using__(which) when is_atom(which) do
    apply(__MODULE__, which, [])
  end
end
