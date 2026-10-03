defmodule Hexpm.Repository.ReleaseDocFiles do
  @moduledoc """
  The documentation files (see `Hexpm.Docs.Files`) recognized in a release's
  tarball, as kind => filename. Written by the Preview upload job so package
  pages can list them without reading preview storage.
  """

  use Hexpm.Schema

  @primary_key false

  schema "release_doc_files" do
    belongs_to :release, Release, primary_key: true
    field :files, :map

    timestamps()
  end
end
