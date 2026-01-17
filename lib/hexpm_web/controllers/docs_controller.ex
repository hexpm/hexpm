defmodule HexpmWeb.DocsController do
  use HexpmWeb, :controller

  def index(conn, _params) do
    redirect(conn, to: ~p"/docs/usage")
  end

  def usage(conn, _params) do
    render(
      conn,
      "layout.html",
      view: "usage.html",
      view_name: :usage,
      title: "Mix usage",
      container: "tw:flex-1 tw:flex tw:flex-col"
    )
  end

  def publish(conn, _params) do
    render(
      conn,
      "layout.html",
      view: "publish.html",
      view_name: :publish,
      title: "Mix publish package",
      container: "tw:flex-1 tw:flex tw:flex-col"
    )
  end

  def tasks(conn, _params) do
    redirect(conn, external: "https://hexdocs.pm/hex")
  end

  def gleam_usage(conn, _params) do
    render(
      conn,
      "layout.html",
      view: "gleam_usage.html",
      view_name: :gleam_usage,
      title: "Gleam usage",
      container: "tw:flex-1 tw:flex tw:flex-col"
    )
  end

  def rebar3_usage(conn, _params) do
    render(
      conn,
      "layout.html",
      view: "rebar3_usage.html",
      view_name: :rebar3_usage,
      title: "Rebar3 usage",
      container: "tw:flex-1 tw:flex tw:flex-col"
    )
  end

  def rebar3_publish(conn, _params) do
    render(
      conn,
      "layout.html",
      view: "rebar3_publish.html",
      view_name: :rebar3_publish,
      title: "Rebar3 publish package",
      container: "tw:flex-1 tw:flex tw:flex-col"
    )
  end

  def rebar3_private(conn, _params) do
    render(
      conn,
      "layout.html",
      view: "rebar3_private.html",
      view_name: :rebar3_private,
      title: "Rebar3 private packages",
      container: "tw:flex-1 tw:flex tw:flex-col"
    )
  end

  def rebar3_tasks(conn, _params) do
    url = "https://rebar3.org/docs/package_management/hex_package_management/"
    redirect(conn, external: url)
  end

  def private(conn, _params) do
    render(
      conn,
      "layout.html",
      view: "private.html",
      view_name: :private,
      title: "Private packages",
      container: "tw:flex-1 tw:flex tw:flex-col"
    )
  end

  def coc(conn, _params) do
    render(
      conn,
      "layout.html",
      view: "coc.html",
      view_name: :coc,
      title: "Code of Conduct",
      container: "tw:flex-1 tw:flex tw:flex-col"
    )
  end

  def faq(conn, _params) do
    render(
      conn,
      "layout.html",
      view: "faq.html",
      view_name: :faq,
      title: "FAQ",
      container: "tw:flex-1 tw:flex tw:flex-col"
    )
  end

  def mirrors(conn, _params) do
    render(
      conn,
      "layout.html",
      view: "mirrors.html",
      view_name: :mirrors,
      title: "Mirrors",
      container: "tw:flex-1 tw:flex tw:flex-col"
    )
  end

  def public_keys(conn, _params) do
    render(
      conn,
      "layout.html",
      view: "public_keys.html",
      view_name: :public_keys,
      title: "Public keys",
      container: "tw:flex-1 tw:flex tw:flex-col"
    )
  end

  def self_hosting(conn, _params) do
    render(
      conn,
      "layout.html",
      view: "self_hosting.html",
      view_name: :self_hosting,
      title: "Self-hosting",
      container: "tw:flex-1 tw:flex tw:flex-col"
    )
  end
end
