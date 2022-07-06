defmodule Hexpm.Search.Parser do
  import NimbleParsec

  @space 0x0020
  whitespace_char = ascii_char([@space])
  quotation_mark = ascii_char([?"])

  sentence =
    ignore(quotation_mark)
    |> utf8_string([not: ?"], min: 1)
    |> ignore(quotation_mark)
    |> post_traverse({:sentence_token, []})

  defp sentence_token(_rest, chars, context, _line, _offset) do
    {[
       sentence:
         chars |> Enum.reverse() |> List.to_string() |> String.split(" ") |> Enum.join(" <-> ")
     ], context}
  end

  word =
    utf8_string(
      [
        not: @space,
        not: ?",
        not: ?(,
        not: ?),
        not: ?&,
        not: ?|
      ],
      min: 1
    )
    |> post_traverse({:word_token, []})

  defp word_token(_rest, chars, context, _line, _offset) do
    {[word: List.to_string(chars |> Enum.reverse())], context}
  end

  input_string =
    choice([
      sentence,
      word
    ])

  # quotation_mark ::= ?"
  # left_bracket   ::= ?(
  # right_bracket  ::= ?)
  # or_            ::= ?|
  # and_           ::= ?&

  # input_string   ::= string_except([quotation_mark, left_bracket, right_bracket, or, and]) | quoted_string_except([quotation_mark])

  # Based upon knowledge @ https://www.youtube.com/watch?v=dDtZLm7HIJs#t=15m54s
  # expression     ::= term or_ expression | term
  # term           ::= factor and_ term | factor
  # factor         ::= left_bracket expression right_bracket | input_string

  left_bracket = ascii_char([?(])
  right_bracket = ascii_char([?)])
  or_ = ascii_char([?|])
  space_or_ = ascii_char([@space])
  and_ = ascii_char([?&])

  defparsec(
    :expression,
    choice([
      parsec(:term)
      |> ignore(optional(whitespace_char))
      |> ignore(times(or_, 1))
      |> ignore(optional(whitespace_char))
      |> parsec(:expression)
      |> tag(:or_by_pipe),
      parsec(:term)
      |> ignore(repeat(space_or_))
      |> parsec(:expression)
      |> tag(:or_by_space),
      parsec(:term)
    ])
  )

  defparsec(
    :term,
    choice([
      parsec(:factor)
      |> ignore(optional(whitespace_char))
      |> ignore(times(and_, 1))
      |> ignore(optional(whitespace_char))
      |> parsec(:term)
      |> tag(:and),
      parsec(:factor)
    ])
  )

  defparsec(
    :factor,
    choice([
      ignore(times(left_bracket, 1))
      |> ignore(optional(whitespace_char))
      |> parsec(:expression)
      |> ignore(optional(whitespace_char))
      |> ignore(times(right_bracket, 1))
      |> tag(:brackets),
      input_string
    ])
  )

  parser =
    parsec(:expression)
    |> ignore(eos())

  defparsec(:parse_sanitized_user_input, parser, debug: false)
end
