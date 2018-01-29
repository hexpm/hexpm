defmodule SafeErlTermTest do
  use ExUnit.Case, async: true

  defmacrop string!(string) do
    quote bind_quoted: [string: string] do
      tokens = :erl_scan.string(string)
      assert :safe_erl_term.string(string) == tokens
    end
  end

  test "works as erl_scan:string/1" do
    string!('''
    {}.
    ''')

    string!('''
    {1, 23, -456}.
    ''')

    string!('''
    {foo, bar, baz}.
    ''')

    string!(~C'''
    {"foo", "bar"}.
    [1, 2, 3].
    ''')

    string!(~C'''
    "foo\nbar\tbaz\123".
    ''')

    string!(~C'''
    'foo\nbar\tbaz\123'.
    ''')

    string!(~C'''
    <<1, 2, "three", 4, 5>>.
    ''')

    string!(~C'''
    <<"åäö"/utf8>>.
    ''')
  end

  test "fails on unknown atoms" do
    assert :safe_erl_term.string('this_should_not_be_known.') ==
             {:error, {1, :safe_erl_term, {:user, 'illegal atom this_should_not_be_known'}}, 1}

    assert :safe_erl_term.string('\'this_should_not_be_known\'.') ==
             {:error, {1, :safe_erl_term, {:user, 'illegal atom this_should_not_be_known'}}, 1}
  end

  test "convert terms" do
    {:ok, tokens, _line} = :safe_erl_term.string('{1, 2, 3}. [foo, bar, baz].')
    assert :safe_erl_term.terms(tokens) == [{1, 2, 3}, [:foo, :bar, :baz]]
  end
end
