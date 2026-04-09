# Decimal

Arbitrary precision decimal arithmetic for Elixir.

## Features

- **Exact arithmetic** with no floating point rounding errors
- Configurable precision and rounding modes
- Supports `+`, `-`, `*`, `/`, `div`, `rem`, and comparison operators

## Installation

Add `decimal` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [{:decimal, "~> 2.0"}]
end
```

## Usage

Basic arithmetic:

```elixir
iex> Decimal.add("0.1", "0.2")
Decimal.new("0.3")

iex> Decimal.mult("3", "0.1")
Decimal.new("0.3")

iex> Decimal.div("1", "3")
Decimal.new("0.3333333333333333333333333333")
```

Comparison:

```elixir
iex> Decimal.compare("1.0", "2.0")
:lt

iex> Decimal.equal?("1.0", "1.00")
true
```

Working with contexts:

```elixir
Decimal.Context.with(%Decimal.Context{precision: 5}, fn ->
  Decimal.div(1, 3)
end)
#=> Decimal.new("0.33333")
```

## Rounding Modes

| Mode | Description |
|------|-------------|
| `:half_up` | Round towards nearest, ties go up |
| `:half_down` | Round towards nearest, ties go down |
| `:half_even` | Round towards nearest, ties go to even (banker's rounding) |
| `:ceiling` | Always round up |
| `:floor` | Always round down |

## Task List

- [x] Basic arithmetic operations
- [x] Configurable precision
- [x] Rounding modes
- [ ] Trigonometric functions
- [ ] Logarithmic functions

## Type Specifications

The main types used:

```elixir
@type t :: %Decimal{sign: 1 | -1, coef: non_neg_integer | :NaN | :inf, exp: integer}
@type decimal :: t | integer | String.t()
```

## Configuration

> **Note:** Global context configuration affects all processes.
> Use `Decimal.Context.with/2` for process-local settings.

Default context:

```elixir
config :decimal,
  precision: 28,
  rounding: :half_up
```

## Details

<details>
<summary>Click to expand internal implementation notes</summary>

The library uses a coefficient-exponent representation internally:

- `sign` - `1` for positive, `-1` for negative
- `coef` - the coefficient as an integer
- `exp` - the exponent (base 10)

So `1.23` is represented as `%Decimal{sign: 1, coef: 123, exp: -2}`.

</details>

## Definition List

Precision
: The number of significant digits used for arithmetic operations.

Rounding
: The method used to reduce the number of significant digits when a result exceeds the precision.

## Keyboard Shortcuts

Use <kbd>Ctrl</kbd>+<kbd>C</kbd> to copy and <kbd>Ctrl</kbd>+<kbd>V</kbd> to paste decimal values.

## Links

See the full [documentation](https://hexdocs.pm/decimal) for more details.

## License

Licensed under the [Apache-2.0](LICENSE) license.
