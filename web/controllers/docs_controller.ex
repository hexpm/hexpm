defmodule HexWeb.DocsController do
  use HexWeb.Web, :controller

  def usage(conn, _params) do
    render conn, "usage.html", [
      title: "Mix usage"
    ]
  end

  def rebar3_usage(conn, _params) do
    render conn, "rebar3_usage.html", [
      title: "Rebar3 usage"
    ]
  end

  def publish(conn, _params) do
    render conn, "publish.html", [
      title: "Mix publish package"
    ]
  end

  def rebar3_publish(conn, _params) do
    render conn, "rebar3_publish.html", [
      title: "Rebar3 publish package"
    ]
  end

  def tasks(conn, _params) do
    render conn, "tasks.html", [
      title: "Mix tasks"
    ]
  end

  def coc(conn, _params) do
    render conn, "coc.html", [
      title: "Code of Conduct"
    ]
  end

  def faq(conn, _params) do
    render conn, "faq.html", [
      title: "FAQ"
    ]
  end

  def mirrors(conn, _params) do
    render conn, "mirrors.html", [
      title: "Mirrors"
    ]
  end

  def public_keys(conn, _params) do
    render conn, "public_keys.html", [
      title: "Public keys"
    ]
  end
end
