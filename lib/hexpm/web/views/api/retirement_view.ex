defmodule Hexpm.Web.API.RetirementView do
  use Hexpm.Web, :view

  def render("show." <> _, %{retirement: retirement}) do
    render_one(retirement, __MODULE__, "show")
  end
  def render("minimal." <> _, %{retirement: retirement}) do
    render_one(retirement, __MODULE__, "minimal")
  end

  def render("show", %{retirement: retirement}) do
    %{
      message: retirement.message,
      reason: retirement.reason,
    }
  end

  def render("minimal", %{retirement: %{retirement: retirement}}) when is_nil(retirement), do: %{}
  def render("minimal", %{retirement: %{retirement: retirement, version: version}}) do
    %{
      version => %{reason: retirement.reason, message: retirement.message}
    }
  end
end
