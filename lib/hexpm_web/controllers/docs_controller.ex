defmodule HexpmWeb.DocsController do
  use HexpmWeb, :controller

  def index(conn, _params) do
    redirect(conn, to: Routes.docs_path(conn, :usage))
  end

  def usage(conn, _params) do
    render(
      conn,
      "layout.html",
      view: "usage.html",
      view_name: :usage,
      title: "Mix usage",
      container: "container page docs"
    )
  end

  def publish(conn, _params) do
    render(
      conn,
      "layout.html",
      view: "publish.html",
      view_name: :publish,
      title: "Mix publish package",
      container: "container page docs"
    )
  end

  def tasks(conn, _params) do
    redirect(conn, external: "https://hexdocs.pm/hex")
  end

  def rebar3_usage(conn, _params) do
    render(
      conn,
      "layout.html",
      view: "rebar3_usage.html",
      view_name: :rebar3_usage,
      title: "Rebar3 usage",
      container: "container page docs"
    )
  end

  def rebar3_publish(conn, _params) do
    render(
      conn,
      "layout.html",
      view: "rebar3_publish.html",
      view_name: :rebar3_publish,
      title: "Rebar3 publish package",
      container: "container page docs"
    )
  end

  def rebar3_tasks(conn, _params) do
    redirect(conn, external: "https://www.rebar3.org/v3.0/docs/hex-package-management")
  end

  def private(conn, _params) do
    render(
      conn,
      "layout.html",
      view: "private.html",
      view_name: :private,
      title: "Private packages",
      container: "container page docs"
    )
  end

  def coc(conn, _params) do
    render(
      conn,
      "layout.html",
      view: "coc.html",
      view_name: :coc,
      title: "Code of Conduct",
      container: "container page docs"
    )
  end

  def faq(conn, _params) do
    render(
      conn,
      "layout.html",
      view: "faq.html",
      view_name: :faq,
      title: "FAQ",
      container: "container page docs"
    )
  end

  def mirrors(conn, _params) do
    render(
      conn,
      "layout.html",
      view: "mirrors.html",
      view_name: :mirrors,
      title: "Mirrors",
      container: "container page docs"
    )
  end

  def public_keys(conn, _params) do
    render(
      conn,
      "layout.html",
      view: "public_keys.html",
      view_name: :public_keys,
      title: "Public keys",
      container: "container page docs"
    )
  end
end
