defmodule Hexpm.Accounts.Seats do
  @moduledoc """
  The single point where a paid seat is claimed or the paid quantity changes.

  Every membership that costs a seat goes through `claim/2`, and every change to
  the subscribed quantity goes through `update_quantity/3`. Both take the same
  row lock on the organization, so a claim and a reduction cannot interleave and
  two claims cannot both spend the last seat.

  The limit comes from `organizations.billing_seats`, which `Hexpm.Billing.Report`
  refreshes every minute and `update_quantity/3` writes through on every change
  hexpm makes itself. Reading it under the lock is what makes the check one
  atomic database operation; a live billing request cannot be, since it would
  hold a transaction open across the network.
  """

  use Hexpm.Context

  @type limit :: :unlimited | {:limited, pos_integer()} | :unknown
  @type usage :: %{organization: Organization.t(), used: non_neg_integer(), limit: limit()}
  @type claim_error :: :seats_exhausted | :seat_limit_unknown

  @doc """
  How many members the organization has paid for.

  `billing_override` comes first because `Hexpm.Billing.Report` marks a comped
  organization active without giving it a seat count, and the raw
  `billing_active` field is used rather than `Organization.billing_active?/1`
  because that folds in the trial and would report trials as unknown.
  """
  @spec limit(Organization.t()) :: limit()
  def limit(%Organization{billing_override: true}), do: :unlimited

  def limit(%Organization{billing_seats: seats}) when is_integer(seats) and seats > 0,
    do: {:limited, seats}

  def limit(%Organization{billing_active: false}), do: :unlimited
  def limit(%Organization{}), do: :unknown

  @doc """
  Current members, counting everyone who occupies a seat.
  """
  @spec used(Organization.t()) :: non_neg_integer()
  def used(organization) do
    Repo.aggregate(assoc(organization, :organization_users), :count)
  end

  @doc """
  Takes the seat lock and returns the organization as it is now.

  `FOR NO KEY UPDATE` rather than `FOR UPDATE`: every insert that references the
  organization takes `FOR KEY SHARE` on this row, and `FOR UPDATE` would block
  all of them for the length of the transaction. Two `FOR NO KEY UPDATE` still
  exclude each other, which is the whole requirement.
  """
  @spec lock!(Organization.t() | pos_integer()) :: Organization.t()
  def lock!(%Organization{id: id}), do: lock!(id)

  def lock!(id) when is_integer(id) do
    Repo.one!(from(o in Organization, where: o.id == ^id, lock: "FOR NO KEY UPDATE"))
  end

  @doc """
  Reserves one seat, or reports why it cannot.

  Must run inside a transaction, and the membership it covers must be inserted
  in that same transaction. Callers pass `unknown: :deny` when the caller is
  automated: an admin naming a user can be allowed through an unknown seat
  count, an identity provider assertion cannot.
  """
  @spec claim(Organization.t(), keyword()) :: {:ok, usage()} | {:error, claim_error()}
  def claim(organization, opts \\ []) do
    unless Repo.in_transaction?() do
      raise ArgumentError,
            "Seats.claim/2 must run inside a transaction, otherwise the lock it takes " <>
              "is released before the membership is inserted"
    end

    count = Keyword.get(opts, :count, 1)
    unknown = Keyword.get(opts, :unknown, :allow)

    organization = lock!(organization)
    used = used(organization)
    limit = limit(organization)

    case limit do
      :unlimited -> {:ok, usage(organization, used, limit)}
      {:limited, seats} when used + count <= seats -> {:ok, usage(organization, used, limit)}
      {:limited, _seats} -> {:error, :seats_exhausted}
      :unknown when unknown == :allow -> {:ok, usage(organization, used, limit)}
      :unknown -> {:error, :seat_limit_unknown}
    end
  end

  @doc """
  `claim/2` as a step in a multi, aborting the transaction when the seat is not
  available.
  """
  @spec claim(Multi.t(), atom(), Organization.t(), keyword()) :: Multi.t()
  def claim(multi, name, organization, opts \\ []) do
    Multi.run(multi, name, fn _repo, _changes -> claim(organization, opts) end)
  end

  @doc """
  Takes the seat lock without reserving anything, so a caller that checks a
  different invariant over the membership set (the last member, the last admin)
  sees a set nobody else can change until it commits.
  """
  @spec lock(Multi.t(), atom(), Organization.t()) :: Multi.t()
  def lock(multi, name, organization) do
    Multi.run(multi, name, fn _repo, _changes -> {:ok, lock!(organization)} end)
  end

  @doc """
  Changes the subscribed quantity, keeping `billing_seats` consistent with what
  the billing service was actually asked for.

  `quantity` may be `:member_count` to subscribe to exactly the current members,
  which is what a first subscription does. `fun` receives the resolved quantity
  and performs the billing call; its return value is passed back to the caller
  untouched.

  A reduction is written before the call and an increase after it, so during the
  window the cached limit is never higher than what has been paid for. A failed
  call puts back the value that was there before, and only if nothing else has
  written since.
  """
  @spec update_quantity(Organization.t(), non_neg_integer() | :member_count, (non_neg_integer() ->
                                                                                result)) ::
          result | {:error, {:seats_below_members, non_neg_integer()}}
        when result: term()
  def update_quantity(organization, quantity, _fun)
      when is_integer(quantity) and quantity < 0 do
    {:error, {:seats_below_members, used(organization)}}
  end

  def update_quantity(organization, quantity, fun)
      when quantity == :member_count or is_integer(quantity) do
    case reserve_quantity(organization, quantity) do
      {:ok, {resolved, previous}} ->
        result = fun.(resolved)
        settle_quantity(organization, result, resolved, previous)
        result

      {:error, _reason} = error ->
        error
    end
  end

  defp reserve_quantity(organization, quantity) do
    Repo.transaction(fn ->
      organization = lock!(organization)
      used = used(organization)
      resolved = if quantity == :member_count, do: used, else: quantity

      if resolved < used do
        Repo.rollback({:seats_below_members, used})
      else
        previous = organization.billing_seats
        if lowers_limit?(previous, resolved), do: write_seats(organization, resolved)
        {resolved, previous}
      end
    end)
  end

  # An increase is not written yet, so nothing can spend a seat that has not
  # been paid for. A reduction is, so nothing can spend a seat that is about to
  # disappear.
  defp lowers_limit?(nil, _resolved), do: false
  defp lowers_limit?(previous, resolved) when is_integer(previous), do: resolved < previous

  defp settle_quantity(organization, {:ok, customer}, resolved, _previous) do
    write_seats(organization, quantity_of(customer, resolved))
  end

  # Anything that is not a plain success leaves the subscription as it was, and
  # that includes a payment that still needs confirming.
  defp settle_quantity(organization, _result, resolved, previous) do
    if lowers_limit?(previous, resolved), do: restore_seats(organization, resolved, previous)
  end

  defp quantity_of(customer, resolved) when is_map(customer) do
    case customer["quantity"] do
      quantity when is_integer(quantity) and quantity > 0 -> quantity
      _other -> resolved
    end
  end

  defp quantity_of(_customer, resolved), do: resolved

  defp write_seats(organization, seats) do
    from(o in Organization, where: o.id == ^organization.id)
    |> Repo.update_all(set: [billing_seats: seats])
  end

  # Conditional on the reserved value so a report that has run in the meantime
  # keeps its answer.
  defp restore_seats(organization, reserved, previous) do
    from(o in Organization, where: o.id == ^organization.id, where: o.billing_seats == ^reserved)
    |> Repo.update_all(set: [billing_seats: previous])
  end

  defp usage(organization, used, limit) do
    %{organization: organization, used: used, limit: limit}
  end
end
