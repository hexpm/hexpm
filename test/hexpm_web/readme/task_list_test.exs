defmodule HexpmWeb.Readme.TaskListTest do
  use ExUnit.Case, async: true

  alias HexpmWeb.Readme.TaskList

  defp parse_and_convert(markdown) do
    {:ok, ast, _} = Earmark.Parser.as_ast(markdown, gfm: true)
    TaskList.convert(ast)
  end

  defp checkbox(checked?) do
    if checked? do
      {"input", [{"type", "checkbox"}, {"checked", "checked"}, {"disabled", "disabled"}], [], %{}}
    else
      {"input", [{"type", "checkbox"}, {"disabled", "disabled"}], [], %{}}
    end
  end

  describe "convert/1" do
    test "converts unchecked checkbox" do
      unchecked_cb = checkbox(false)
      ast = parse_and_convert("- [ ] unchecked\n")
      [{"ul", _, [{"li", _, children, _}], _}] = ast
      assert [^unchecked_cb, "unchecked"] = children
    end

    test "converts checked checkbox with lowercase x" do
      checked_cb = checkbox(true)
      ast = parse_and_convert("- [x] checked\n")
      [{"ul", _, [{"li", _, children, _}], _}] = ast
      assert [^checked_cb, "checked"] = children
    end

    test "converts checked checkbox with uppercase X" do
      checked_cb = checkbox(true)
      ast = parse_and_convert("- [X] checked\n")
      [{"ul", _, [{"li", _, children, _}], _}] = ast
      assert [^checked_cb, "checked"] = children
    end

    test "does not convert normal list items" do
      ast = parse_and_convert("- normal item\n")
      [{"ul", _, [{"li", _, ["normal item"], _}], _}] = ast
    end

    test "does not convert checkbox not at start of item" do
      ast = parse_and_convert("- not [x] a checkbox\n")
      [{"ul", _, [{"li", _, ["not [x] a checkbox"], _}], _}] = ast
    end

    test "converts checkboxes in loose lists (with p tags)" do
      unchecked_cb = checkbox(false)
      checked_cb = checkbox(true)
      ast = parse_and_convert("- [ ] unchecked\n\n- [x] checked\n")
      [{"ul", _, items, _}] = ast

      assert [
               {"li", _, [{"p", _, [^unchecked_cb, "unchecked"], _}], _},
               {"li", _, [{"p", _, [^checked_cb, "checked"], _}], _}
             ] = items
    end

    test "converts checkbox with formatted text after" do
      unchecked_cb = checkbox(false)
      ast = parse_and_convert("- [ ] **bold** text\n")
      [{"ul", _, [{"li", _, children, _}], _}] = ast
      assert [^unchecked_cb, {"strong", _, ["bold"], _}, " text"] = children
    end

    test "converts checkbox without trailing text" do
      unchecked_cb = checkbox(false)
      checked_cb = checkbox(true)
      ast = parse_and_convert("- [ ]\n- [x]\n")
      [{"ul", _, items, _}] = ast

      assert [
               {"li", _, [^unchecked_cb], _},
               {"li", _, [^checked_cb], _}
             ] = items
    end

    test "mixed list with checkboxes and normal items" do
      unchecked_cb = checkbox(false)
      checked_cb = checkbox(true)
      ast = parse_and_convert("- [ ] todo\n- [x] done\n- normal\n")
      [{"ul", _, items, _}] = ast

      assert [
               {"li", _, [^unchecked_cb, "todo"], _},
               {"li", _, [^checked_cb, "done"], _},
               {"li", _, ["normal"], _}
             ] = items
    end

    test "does not affect non-list content" do
      ast = parse_and_convert("# Title\n\nSome paragraph.\n")
      assert [{"h1", _, ["Title"], _}, {"p", _, ["Some paragraph."], _}] = ast
    end
  end
end
