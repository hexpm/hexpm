# CHANGELOG

## Unreleased

### Enhancements

* Reduce the cost of every operation that goes through the context: results
  that signal nothing no longer copy the context or write it back to the
  process dictionary, the coefficient's digit count is computed once per
  operation instead of up to four times, and digit counting no longer walks a
  ladder of bignum comparisons before falling back to its estimate. Division
  is ~1.9x faster, `add`/`sub`/`mult`/`round`/`normalize` ~1.3x, comparison of
  same-scale values ~1.4x, parsing ~1.2x, all with 20-30% less allocation.

* Make `Decimal.to_float/1` scale the operand with a computed shift instead of
  one bit at a time: ~1.6x faster for typical values and ~11x for exponents
  near the ends of the double range, with 96% fewer collections.

### Bug fixes

* Fix `Decimal.div/2` rounding the wrong way on inexact results. The long
  division discarded its remainder instead of carrying it into rounding as
  a sticky bit, so a guard digit of 5 with a nonzero tail was treated as an
  exact tie (`:half_even`/`:half_down`) and a guard digit of 0 with a
  nonzero tail was treated as zero (`:ceiling`/`:floor`/`:up`). Roughly 5%
  of random divisions at the default precision were affected, including
  `:ceiling`/`:floor` returning a result on the wrong side of the true
  value. The same remainder is now also reflected in the `:inexact` flag,
  which was previously suppressed when the remainder was a power of ten.

* Re-round the coefficient when a rounding carry lengthens it past the
  context precision. Rounding an all-nines coefficient up (e.g. `9.99` to
  precision 2, or `Decimal.div(95, 10)` at precision 1) produced a
  coefficient with one digit more than `precision` (`d(1, 100, -1)`,
  `d(1, 10, 0)`) instead of re-rounding to exactly `precision` significant
  digits (`d(1, 10, 0)`, `d(1, 1, 1)`). This affects every context
  operation (`add`, `sub`, `mult`, `div`) and now matches the General
  Decimal Arithmetic spec and Python's decimal.

## v3.1.1 (2026-05-27)

### Bug fixes

* Fix `Decimal.parse/2` and `Decimal.new/2` rejecting inspect output for
  values at the context's full precision with negative exponents (e.g.
  `Decimal.new("0.3162277660168379331998893544432719")`). The
  `:max_digits` limit no longer counts non-significant leading zeros.

## v3.1.0 (2026-05-08)

### Enhancements

* `Decimal.new/2` now accepts an optional `opts` keyword list and
  forwards it to `Decimal.parse/2`, allowing callers to override
  `:max_digits` and `:max_exponent` when constructing a decimal from
  a string.

### Bug fixes

* Fix infinite loop in `Decimal.to_integer/1` when the coefficient is
  zero and the exponent is negative (e.g. `Decimal.new("0.0")`). Such
  values now correctly convert to the integer `0`.

## v3.0.0 (2026-05-07)

### Note on the new defaults

The new decimal128 defaults are more than sufficient for currency and
other real-world numeric use cases. With `precision: 34` and a scale of
2 (two digits after the decimal point for cents), values from `0.00` up
to roughly `99_999_999_999_999_999_999_999_999_999_999.99` (~10³², 100
nonillion) round-trip without rounding. Most upgrades from 2.x require
no code changes.

### Security

* Make the v2.4.0 mitigations for CVE-2026-32686 the default. The
  default `Decimal.Context` and the public parse, cast, and to_string
  functions now follow IEEE 754 decimal128 limits, rejecting inputs
  such as `1e1000000000` without materializing them.

### Breaking changes

* `Decimal.Context` defaults change from precision `28` and unbounded
  `emax`/`emin` to decimal128 values: `precision: 34`, `emax: 6_144`,
  `emin: -6_143`. Operation results whose adjusted exponent leaves that
  band signal overflow or underflow.
* `Decimal.parse/1` and `Decimal.cast/1` reject inputs whose digit count
  exceeds `34` (decimal128 precision) or whose absolute exponent exceeds
  `6_144` (decimal128 emax). Use `parse/2` / `cast/2` with
  `max_digits: :infinity` and `max_exponent: :infinity` to restore
  unbounded behavior.
* `Decimal.parse/2` and `Decimal.cast/2` default `:max_digits` to `34`
  and `:max_exponent` to `6_144` when not specified.
* `Decimal.to_string/2` and `Decimal.to_string/3` raise `ArgumentError`
  when the rendered output would exceed `6_178` digit characters
  (precision + emax — the worst-case `:normal` width of any in-range
  decimal128 value). `Inspect`, `String.Chars`, and `JSON.Encoder`
  protocol implementations pass `max_digits: :infinity` so debug output
  always succeeds.

## v2.4.0 (2026-05-07)

### Security

* Mitigate exponent amplification (CVE-2026-32686).
  Compact inputs such as `1e1000000` could force multi-second expansions
  during arithmetic, parsing, normalization, comparison, or formatting.
  `Decimal.add/2` and `Decimal.sub/2` now scale operands to `precision + 2`
  digits with a sticky bit instead of materializing the full coefficient.

### Enhancements

* Add `:max_digits` and `:max_exponent` options to `Decimal.parse/2` and
  `Decimal.cast/2` to reject pathological inputs without expansion
* Add `:max_digits` option to `Decimal.to_string/3` to cap formatted output
  before materialization
* Add `:emax` and `:emin` fields to `Decimal.Context` for IBM General Decimal
  Arithmetic-style overflow and underflow signaling
* Optimize hot paths for large decimals: `coef_length`, `normalize`,
  `to_integer`, `integer?`, parsing, and large-coefficient string formatting

## v2.3.0 (2024-12-13)

* Implement the upcoming [`JSON.Encoder`](https://hexdocs.pm/elixir/main/JSON.Encoder.html)
  protocol

## v2.2.0 (2024-11-13)

* Add `Decimal.gte?/2` and `Decimal.lte?/2`
* Add `Decimal.compare/3` and `Decimal.eq?/3` with threshold as parameter

## v2.1.1 (2023-04-26)

Decimal v2.1 requires Elixir v1.8+.

### Bug fixes

* Fix `Decimal.compare/2` when comparing against `0`

## v2.1.0 (2023-04-26)

Decimal v2.1 requires Elixir v1.8+.

### Enhancements

* Improve error message from `Decimal.to_integer/1` during precision loss
* `Inspect` protocol implementation returns strings in the `Decimal.new(...)` format
* Add `Decimal.scale/1`
* Optimize `Decimal.compare/2` for numbers with large exponents

### Bug fixes

* Fix `Decimal.integer?/1` spec
* Fix `Decimal.integer?/1` check on 0 with >1 significant digits

## v2.0.0 (2020-09-08)

Decimal v2.0 requires Elixir v1.2+.

### Enhancements

* Add `Decimal.integer?/1`

### Breaking changes

* Change `Decimal.compare/2` to return `:lt | :eq | :gt`
* Change `Decimal.cast/1` to return `{:ok, t} | :error`
* Change `Decimal.parse/1` to return `{t, binary} | :error`
* Remove `:message` and `:result` fields from `Decimal.Error`
* Remove sNaN
* Rename qNaN to NaN
* Remove deprecated support for floats in `Decimal.new/1`
* Remove deprecated `Decimal.minus/1`
* Remove deprecated `Decimal.plus/1`
* Remove deprecated `Decimal.reduce/1`
* Remove deprecated `Decimal.with_context/2`, `Decimal.get_context/1`, `Decimal.set_context/1`,
  and `Decimal.update_context/1`
* Remove deprecated `Decimal.decimal?/1`

### Deprecations

* Deprecate `Decimal.cmp/2`

## v1.9.0 (2020-09-08)

### Enhancements

* Add `Decimal.negate/1`
* Add `Decimal.apply_context/1`
* Add `Decimal.normalize/1`
* Add `Decimal.Context.with/2`, `Decimal.Context.get/1`, `Decimal.Context.set/2`,
  and `Decimal.Context.update/1`
* Add `Decimal.is_decimal/1`

### Deprecations

* Deprecate `Decimal.minus/1` in favour of the new `Decimal.negate/1`
* Deprecate `Decimal.plus/1` in favour of the new `Decimal.apply_context/1`
* Deprecate `Decimal.reduce/1` in favour of the new `Decimal.normalize/1`
* Deprecate `Decimal.with_context/2`, `Decimal.get_context/1`, `Decimal.set_context/2`,
  and `Decimal.update_context/1` in favour of new functions on the `Decimal.Context` module
* Deprecate `Decimal.decimal?/1` in favour of the new `Decimal.is_decimal/1`

## v1.8.1 (2019-12-20)

### Bug fixes

* Fix Decimal.compare/2 with string arguments
* Set :signal on error

## v1.8.0 (2019-06-24)

### Enhancements

* Add `Decimal.cast/1`
* Add `Decimal.eq?/2`, `Decimal.gt?/2`, and `Decimal.lt?/2`
* Add guards to `Decimal.new/3` to prevent invalid Decimal numbers

## v1.7.0 (2019-02-16)

### Enhancements

* Add `Decimal.sqrt/1`

## v1.6.0 (2018-11-22)

### Enhancements

* Support for canonical XSD representation on `Decimal.to_string/2`

### Bugfixes

* Fix exponent off-by-one when converting from decimal to float
* Fix negative?/1 and positive?/1 specs

### Deprecations

* Deprecate passing float to `Decimal.new/1` in favor of `Decimal.from_float/1`

## v1.5.0 (2018-03-24)

### Enhancements

* Add `Decimal.positive?/1` and `Decimal.negative?/1`
* Accept integers and strings in arithmetic functions, e.g.: `Decimal.add(1, "2.0")`
* Add `Decimal.from_float/1`

### Soft deprecations (no warnings emitted)

* Soft deprecate passing float to `new/1` in favor of `from_float/1`

## v1.4.1 (2017-10-12)

### Bugfixes

* Include the given value as part of the error reason
* Fix `:half_even` `:lists.last` bug (empty signif)
* Fix error message for round
* Fix `:half_down` rounding error when remainder is greater than 5
* Fix `Decimal.new/1` float conversion with bigger precision than 4
* Fix precision default value

## v1.4.0 (2017-06-25)

### Bugfixes

* Fix `Decimal.to_integer/1` for large coefficients
* Fix rounding of ~0 values
* Fix errors when comparing and adding two infinities
