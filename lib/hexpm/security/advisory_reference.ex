defmodule Hexpm.Security.AdvisoryReference do
  use Hexpm.Schema

  schema "security_advisory_references" do
    field :advisory_id, :string
    field :type, :string
    field :url, :string
  end

  @valid_url_schemes ~w(http https)

  def changeset(reference, params) do
    reference
    |> cast(params, ~w(type url)a)
    |> validate_required(~w(type url)a)
    |> validate_length(:url, max: 2000)
    |> validate_change(:url, fn :url, url ->
      case URI.parse(url) do
        %URI{scheme: scheme, host: host}
        when scheme in @valid_url_schemes and is_binary(host) and host != "" ->
          []

        _ ->
          [url: "must be an http or https URL"]
      end
    end)
  end
end
