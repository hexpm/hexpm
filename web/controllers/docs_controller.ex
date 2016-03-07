defmodule HexWeb.DocsController do
  use HexWeb.Web, :controller

  def usage(conn, _params) do
    render conn, "usage.html", [
      active: :docs,
      title: "Mix Usage"
    ]
  end

  def rebar3_usage(conn, _params) do
    render conn, "rebar3_usage.html", [
      active: :docs,
      title: "Rebar3 Usage"
    ]
  end

  def publish(conn, _params) do
    render conn, "publish.html", [
      active: :docs,
      title: "Mix publish package"
    ]
  end

  def rebar3_publish(conn, _params) do
    render conn, "rebar3_publish.html", [
      active: :docs,
      title: "Rebar3 publish package"
    ]
  end

  def tasks(conn, _params) do
    render conn, "tasks.html", [
      active: :docs,
      title: "Mix tasks"
    ]
  end

  def coc(conn, _params) do
    render conn, "coc.html", [
      active: :docs,
      title: "Code of Conduct"
    ]
  end

  def faq(conn, _params) do
    render conn, "faq.html", [
      active: :docs,
      title: "FAQ"
    ]
  end

  def mirrors(conn, _params) do
    render conn, "mirrors.html", [
      active: :docs,
      title: "Mirrors"
    ]
  end

  def public_keys(conn, _params) do
    render conn, "public_keys.html", [
      active: :docs,
      title: "Public keys"
    ]
  end
end
