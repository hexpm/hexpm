defmodule Hexpm.AdminTasks.Reasons do
  @moduledoc """
  Canned reasons for the `:reason` option on the removal tasks.

  Pass an id to send the matching text, or a string to send that string.

  Each text follows the sentence that already named what was removed, so it
  states the rule that was broken and never repeats the package name, the
  version, or the username. A reason lists the scopes it makes sense for:
  `:empty` explains a package and explains nothing about an account.

      iex> AdminTasks.reasons(:user) |> Keyword.keys()
      [:seo_spam, :typosquatting, :undisclosed_behaviour, :malware, :spam_account,
       :owner_request, :terms_of_service]
  """

  @scopes [:package, :release, :user]

  @reasons [
    %{
      id: :seo_spam,
      scopes: [:package, :release, :user],
      text:
        "Hex.pm does not accept packages published to advertise a website. " <>
          "What was published provided no working software, only links and text " <>
          "pointing at an unrelated site."
    },
    %{
      id: :empty,
      scopes: [:package, :release],
      text:
        "There was no working software here, only an empty or unfinished " <>
          "skeleton with nothing implemented behind it."
    },
    %{
      id: :name_squatting,
      scopes: [:package],
      text:
        "The package held a name without providing software. Hex.pm does not " <>
          "reserve names for projects that have not been published."
    },
    %{
      id: :typosquatting,
      scopes: [:package, :release, :user],
      text:
        "The name closely imitated an existing Hex.pm package. Names chosen to " <>
          "be mistaken for another package are not allowed."
    },
    %{
      id: :copyright,
      scopes: [:package, :release],
      text: "The package redistributed someone else's work without the right to do so."
    },
    %{
      id: :undisclosed_behaviour,
      scopes: [:package, :release, :user],
      text:
        "The code did something it never disclosed, such as reading credentials " <>
          "or contacting a remote server at build time. Hex.pm removes packages " <>
          "that hide behaviour from the people installing them."
    },
    %{
      id: :malware,
      scopes: [:package, :release, :user],
      text:
        "The code was malicious and attempted to compromise the machines of " <>
          "anyone who installed it."
    },
    %{
      id: :spam_account,
      scopes: [:user],
      text:
        "The account was used to publish spam. Every package it published was " <>
          "advertising or filler rather than working software."
    },
    %{
      id: :owner_request,
      scopes: [:package, :release, :user],
      text: "The owner asked us to remove it."
    },
    %{
      id: :terms_of_service,
      scopes: [:package, :release, :user],
      text: "This broke the Hex.pm terms of service."
    }
  ]

  @doc """
  Every reason usable for `scope`, as `{id, text}` pairs.
  """
  @spec all(:package | :release | :user) :: keyword(String.t())
  def all(scope) when scope in @scopes do
    for reason <- @reasons, scope in reason.scopes, do: {reason.id, reason.text}
  end

  @doc """
  Resolves a `:reason` value to the text that goes in the email.

  A string is its own text. An id has to be one the scope allows, and an
  unknown id is an error rather than a silent fallback: the removal tasks
  resolve the reason before they delete anything, so a typo costs nothing.
  """
  @spec fetch(:package | :release | :user, atom() | String.t()) ::
          {:ok, String.t()} | {:error, {:unknown_reason, term()}}
  def fetch(scope, text) when scope in @scopes and is_binary(text) do
    {:ok, text}
  end

  def fetch(scope, id) when scope in @scopes do
    case Enum.find(@reasons, &(&1.id == id and scope in &1.scopes)) do
      nil -> {:error, {:unknown_reason, id}}
      reason -> {:ok, reason.text}
    end
  end
end
