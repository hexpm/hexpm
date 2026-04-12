defmodule Hexpm.Repository.Package.SearchQuery do
  @moduledoc false

  defstruct free_text: nil,
            depends: nil,
            build_tools: [],
            updated_after: nil,
            extra: [],
            name: nil,
            description: nil,
            unknown: []

  def parse(_string), do: raise("not implemented")
  def serialize(_query), do: raise("not implemented")
end
