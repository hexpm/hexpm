defmodule Hexpm.Search.Sanitizer do
  require Integer

  def sanitize(string) do
    string
    |> remove_ascii_control_characters()
    |> remove_surplus_whitespace()
    # |> remove_empty_round_brackets(n)
    |> remove_inner_white_space_padding_within_quoted_sub_strings()
    |> remove_inner_white_space_padding_within_round_brackets()
    |> space_pad_double_quotes()
    |> balance_double_quotes()
    # |> balance_non_quoted_round_brackets()
    |> balance_logical_operators()
  end

  def remove_ascii_control_characters(string) do
    Regex.replace(~r/\p{C}/u, string, " ")
  end

  def space_pad_double_quotes(string) do
    Regex.replace(~r/"/u, string, " \" ")
  end

  def remove_surplus_whitespace(string) do
    Regex.replace(~r/\s+/u, string, " ")
    |> String.trim()
  end

  # TODO ask inoas what this is for and how to use it
  def take_graphemes_at_max_bytes(string, max_bytes) do
    string
    |> String.graphemes()
    |> Enum.reduce_while("", fn character, accumulator ->
      if byte_size(accumulator <> character) <= max_bytes do
        {:cont, accumulator <> character}
      else
        {:halt, accumulator}
      end
    end)
  end

  # Append quote char if not balanced even
  def balance_double_quotes(string) do
    string =
      if string |> String.split("") |> Enum.count(&(&1 == "\"")) |> Integer.is_odd(),
        do: string <> "\"",
        else: string

    # Replace potentially empty quotes
    Regex.replace(~r/"\s{0,}"/u, string, "")
  end

  # not sure how I should use this
  def balance_non_quoted_round_brackets(string, round_bracket_nesting_limit) do
    string
    |> String.graphemes()
    |> Enum.reduce({"", false, 0}, fn character, accumulator ->
      {new_string, is_within_quoted_string, opened_count} = accumulator

      case {character, is_within_quoted_string} do
        # Toggle if we are within quotes - round brackets within quotes are being ignored
        {"\"", is_within_quoted_string} ->
          {new_string <> character, not is_within_quoted_string, opened_count}

        {"(", true} ->
          {new_string <> "(", is_within_quoted_string, opened_count}

        {")", true} ->
          {new_string <> ")", is_within_quoted_string, opened_count}

        {"(", false} ->
          if opened_count + 1 <= round_bracket_nesting_limit do
            {new_string <> " ( ", is_within_quoted_string, opened_count + 1}
          else
            {new_string, is_within_quoted_string, opened_count}
          end

        {")", false} ->
          # If there are no opened round brackets, then we cannot close them
          if opened_count == 0 do
            {new_string, is_within_quoted_string, opened_count}
          else
            {new_string <> " ) ", is_within_quoted_string, opened_count - 1}
          end

        _ ->
          {new_string <> character, is_within_quoted_string, opened_count}
      end
    end)
    # Finally we close any surplus opened round bracket
    |> then(fn {new_string, _is_within_quoted_string, opened_count} ->
      new_string <> String.duplicate(" ) ", opened_count)
    end)
  end

  def remove_inner_white_space_padding_within_quoted_sub_strings(string) do
    reducer_fn = fn character, accumulator ->
      {new_string, is_within_quoted_string, do_ignore_next_space} = accumulator

      case {character, is_within_quoted_string, do_ignore_next_space} do
        # Toggle if we are within quotes - round brackets within quotes are being ignored
        {"\"", _, _} ->
          {new_string <> character, not is_within_quoted_string, not is_within_quoted_string}

        # Encounter whitespace within quotes while do_ignore_next_space is true
        {" ", true, true} ->
          {new_string, true, true}

        # Encounter whitespace within quotes while do_ignore_next_space is false
        {" ", true, false} ->
          {new_string <> character, true, true}

        # Encounter whitespace outside of quotes, simply append
        {" ", false, _} ->
          {new_string <> character, is_within_quoted_string, false}

        # Encounter any other character, reset do_ignore_next_space
        _ ->
          {new_string <> character, is_within_quoted_string, false}
      end
    end

    # TODO: Do not call String.graphemes/1 String.reverse/1 multiple times but work on list of char and benchmark with https://hexdocs.pm/benchee/readme.html
    string
    |> String.graphemes()
    |> Enum.reduce({"", false, false}, reducer_fn)
    |> then(fn {new_string, _is_within_quoted_string, _do_ignore_next_space} ->
      new_string
    end)
    |> String.reverse()
    |> String.graphemes()
    |> Enum.reduce({"", false, false}, reducer_fn)
    |> then(fn {new_string, _is_within_quoted_string, _do_ignore_next_space} ->
      new_string
    end)
    |> String.reverse()
  end

  def balance_logical_operators(string) do
    reducer_fn = fn character, accumulator ->
      {direction, new_string, is_within_quoted_string, can_next_be_operator} = accumulator

      case {direction, character, is_within_quoted_string, can_next_be_operator} do
        # Toggle if we are within quotes - operators within quotes are being ignored
        {direction, "\"", _, _} ->
          {direction, new_string <> character, not is_within_quoted_string,
           not is_within_quoted_string}

        # Encounter and-operator outside quotes while can_next_be_operator == true: append & can_next_be_operator = true
        {direction, "&", false, true} ->
          {direction, new_string <> " " <> character <> " ", false, false}

        # Encounter and-operator outside quotes while can_next_be_operator == false: ignore & can_next_be_operator = true
        {direction, "&", false, false} ->
          {direction, new_string, false, false}

        # Encounter or-operator outside quotes while can_next_be_operator == true: append & can_next_be_operator = true
        {direction, "|", false, true} ->
          {direction, new_string <> " " <> character <> " ", false, false}

        # Encounter or-operator outside quotes while can_next_be_operator == false: ignore & can_next_be_operator = true
        {direction, "|", false, false} ->
          {direction, new_string, false, false}

        # Encounter whitespace outside of quotes: append & pass through can_next_be_operator
        {direction, " ", false, _} ->
          {direction, new_string <> character, false, can_next_be_operator}

        # Encounter an opening bracket in LTR mode: append & can_next_be_operator = false
        {"LTR", "(", false, false} ->
          {direction, new_string <> character, false, false}

        # Encounter an opening bracket in RTL mode: append & can_next_be_operator = true
        {"RTL", "(", false, false} ->
          {direction, new_string <> character, false, true}

        # Encounter a closing bracket in RTL mode: append & can_next_be_operator = false
        {"RTL", ")", false, false} ->
          {direction, new_string <> character, false, false}

        # Encounter a closing bracket in LTR mode: append & can_next_be_operator = true
        {"LTR", ")", false, false} ->
          {direction, new_string <> character, false, true}

        # Encounter any other character, outside of quotes: ignore & can_next_be_operator = false
        {direction, _, false, _} ->
          {direction, new_string <> character, false, true}

        # Encounter any other character, inside of quotes: append & can_next_be_operator = false
        {direction, _, true, _} ->
          {direction, new_string <> character, true, true}
      end
    end

    # TODO: Do not call String.graphemes/1 String.reverse/1 multiple times but work on list of char and benchmark with https://hexdocs.pm/benchee/readme.html
    string
    |> String.graphemes()
    |> Enum.reduce({"LTR", "", false, false}, reducer_fn)
    |> then(fn {_direction, new_string, _is_within_quoted_string, _can_next_be_operator} ->
      new_string
    end)
    |> String.reverse()
    |> String.graphemes()
    |> Enum.reduce({"RTL", "", false, false}, reducer_fn)
    |> then(fn {_direction, new_string, _is_within_quoted_string, _can_next_be_operator} ->
      new_string
    end)
    |> String.reverse()
  end

  # TODO Same
  def remove_empty_round_brackets(string, 0) do
    string
  end

  def remove_empty_round_brackets(string, n) do
    remove_empty_round_brackets(
      Regex.replace(~r/\({#{Integer.to_string(n)}}\s*\){#{Integer.to_string(n)}}/, string, ""),
      n - 1
    )
  end

  def remove_inner_white_space_padding_within_round_brackets(string) do
    reducer_fn = fn character, accumulator ->
      {direction, new_string, is_within_quoted_string, is_prev_char_bracket} = accumulator

      case {direction, character, is_within_quoted_string, is_prev_char_bracket} do
        # Toggle if we are within quotes - operators within quotes are being ignored
        {direction, "\"", _, _} ->
          {direction, new_string <> character, not is_within_quoted_string,
           not is_within_quoted_string}

        # Encounter bracket outside quotes while is_prev_char_bracket == false: append & is_prev_char_bracket = true
        {"LTR", "(", false, _} ->
          {direction, new_string <> character, false, true}

        {"RTL", ")", false, _} ->
          {direction, new_string <> character, false, true}

        # Encounter whitespace outside of quotes while is_prev_char_bracket == true: ignore & is_prev_char_bracket = true
        {direction, " ", false, true} ->
          {direction, new_string, false, true}

        # Encounter whitespace outside of quotes while is_prev_char_bracket == false: append & is_prev_char_bracket = false
        {direction, " ", false, false} ->
          {direction, new_string <> character, false, false}

        # Encounter any other character, outside of quotes: ignore & is_prev_char_bracket = false
        {direction, _, false, _} ->
          {direction, new_string <> character, false, false}

        # Encounter any other character, inside of quotes: append & is_prev_char_bracket = false
        {direction, _, true, _} ->
          {direction, new_string <> character, true, false}
      end
    end

    # TODO: Do not call String.graphemes/1 String.reverse/1 multiple times but work on list of char and benchmark with https://hexdocs.pm/benchee/readme.html
    string
    |> String.graphemes()
    |> Enum.reduce({"LTR", "", false, false}, reducer_fn)
    |> then(fn {_direction, new_string, _is_within_quoted_string, _is_prev_char_bracket} ->
      new_string
    end)
    |> String.reverse()
    |> String.graphemes()
    |> Enum.reduce({"RTL", "", false, false}, reducer_fn)
    |> then(fn {_direction, new_string, _is_within_quoted_string, _is_prev_char_bracket} ->
      new_string
    end)
    |> String.reverse()
  end
end
