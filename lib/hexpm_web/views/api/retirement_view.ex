defmodule HexpmWeb.API.RetirementView do
  use HexpmWeb, :view

  def render("show." <> _, %{retirement: retirement}) do
    render_one(retirement, __MODULE__, "show")
  end

  def render("package." <> _, %{retirement: retirement}) do
    render_one(retirement, __MODULE__, "package")
  end

  def render("show", %{retirement: retirement}) do
    %{
      message: retirement.message,
      reason: retirement.reason
    }
  end

  def render("package", %{retirement: %{retirement: nil}}), do: %{}

  def render("package", %{retirement: %{retirement: retirement, version: version}}) do
    %{
      version => %{reason: retirement.reason, message: retirement.message}
    }
  end
end
