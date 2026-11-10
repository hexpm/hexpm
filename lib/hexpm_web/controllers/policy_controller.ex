defmodule HexpmWeb.PolicyController do
  use HexpmWeb, :controller

  def coc(conn, _params) do
    render(
      conn,
      "coc.html",
      title: "Code of Conduct",
      container: "flex-1 flex flex-col"
    )
  end

  def copyright(conn, _params) do
    render(
      conn,
      "copyright.html",
      title: "Copyright Policy",
      container: "flex-1 flex flex-col"
    )
  end

  def privacy(conn, _params) do
    render(
      conn,
      "privacy.html",
      title: "Privacy Policy",
      container: "flex-1 flex flex-col"
    )
  end

  def tos(conn, _params) do
    render(
      conn,
      "tos.html",
      title: "Terms of Service",
      container: "flex-1 flex flex-col"
    )
  end

  def package_transfer(conn, _params) do
    render(
      conn,
      "package_transfer.html",
      title: "Package Transfer Policy",
      container: "flex-1 flex flex-col"
    )
  end

  def account_recovery(conn, _params) do
    render(
      conn,
      "account_recovery.html",
      title: "Account Recovery Policy",
      container: "flex-1 flex flex-col"
    )
  end

  def subprocessors(conn, _params) do
    render(
      conn,
      "subprocessors.html",
      title: "Subprocessors",
      container: "flex-1 flex flex-col"
    )
  end

  def dpa(conn, _params) do
    render(
      conn,
      "dpa.html",
      title: "Data Processing Agreement",
      container: "flex-1 flex flex-col"
    )
  end

  def security(conn, _params) do
    render(
      conn,
      "security.html",
      title: "Security",
      container: "flex-1 flex flex-col"
    )
  end
end
