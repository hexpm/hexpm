defmodule Hexpm.Accounts.BlockedEmailDomain do
  use Hexpm.Schema

  @moduledoc """
  A domain whose addresses cannot be added to an account.

  A block covers the domain and everything under it, so blocking `example.com`
  also blocks `mail.example.com`. Addresses that already exist are untouched.
  """

  schema "blocked_email_domains" do
    field :domain, :string
    field :comment, :string

    timestamps(updated_at: false)
  end

  def changeset(blocked_domain, params) do
    cast(blocked_domain, params, ~w(domain comment)a)
    |> validate_required(~w(domain)a)
    |> update_change(:domain, &normalize/1)
    |> validate_length(:domain, count: :bytes, max: 253)
    |> validate_length(:comment, count: :codepoints, max: 255)
    |> validate_format(:domain, ~r/^[^\s@]+\.[^\s@.]+$/)
    |> unique_constraint(:domain)
  end

  @doc "Every blocked domain an address falls under."
  def by_email(email) do
    domains =
      email
      |> String.split("@")
      |> List.last()
      |> normalize()
      |> suffixes()

    from(b in __MODULE__, where: b.domain in ^domains)
  end

  def by_domain(domain) do
    from(b in __MODULE__, where: b.domain == ^normalize(domain))
  end

  defp normalize(domain), do: domain |> String.trim() |> String.downcase()

  defp suffixes(domain) do
    labels = String.split(domain, ".")

    for n <- 2..length(labels)//1, do: labels |> Enum.take(-n) |> Enum.join(".")
  end
end
