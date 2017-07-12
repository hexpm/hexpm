defmodule Hexpm.Web.API.RetirementView do
  use Hexpm.Web, :view

  def render("show." <> _, %{retirement: retirement}) do
    render_one(retirement, __MODULE__, "show")
  end

  def render("show", %{retirement: retirement}) do
    %{
      message: retirement.message,
      reason: retirement.reason,
    }
  end
end
