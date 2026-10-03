defmodule Hexpm.ShortURLs.Target do
  use Hexpm.Schema

  schema "short_url_targets" do
    field :url, :string
    field :url_hash, :binary

    timestamps(updated_at: false)
  end

  def url_hash(url) when is_binary(url), do: :crypto.hash(:sha256, url)
end
