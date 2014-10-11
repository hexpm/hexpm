defmodule HexWeb.Email do
  use Behaviour

  defcallback send(String.t, binary, binary) :: term
  defcallback send(String.t, String.t, binary, binary) :: term
  defcallback send(String.t, String.t, binary, binary, String.t, String.t, String.t, Integer.t) :: term


  @templates [
    :confirmation_request,
    :confirmed
  ]

  Enum.each(@templates, fn name ->
    name = Atom.to_string(name)
    file = Path.join([__DIR__, "templates", "#{path}.eex"])
    EEx.function_from_file(:def, :"template_#{name}", file, [:assigns])
  end)

  def render(name, assigns) do
    fun = :"template_#{name}"
    apply(__MODULE__, fun, [assigns])
  end
end
