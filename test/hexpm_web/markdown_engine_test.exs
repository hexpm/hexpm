defmodule HexpmWeb.MarkdownEngineTest do
  use ExUnit.Case, async: true

  @markdown """
  ## FAQ

  ### Contact

  #### How do I contact Hex?

  To report an issue in Hex or its services open an issue on the appropriate repository in the [GitHub organization](https://github.com/hexpm) or on the [hexpm repository](https://github.com/hexpm/hexpm/issues).
  To get in direct contact with Hex core team email [support@hex.pm](mailto:support@hex.pm).

  ### How do I report a security issue?

  Security vulnerabilities should be disclosed to [security@hex.pm](mailto:security@hex.pm).
  """

  @icon HexpmWeb.ViewIcons.icon(:heroicon, :link, class: "icon-link")
        |> Phoenix.HTML.safe_to_string()

  @tmp_dir Application.compile_env(:hexpm, :tmp_dir)

  test "does not change h2 tags" do
    html = render_markdown()
    assert html =~ "<h2>"
  end

  test "adds anchors to h3 tags" do
    html = render_markdown()

    assert html =~ ~s(<h3 id="contact" class="section-heading">)
    assert html =~ ~s(<a href="#contact" class="hover-link">)
    assert html =~ @icon
    assert html =~ "Contact</h3>"
  end

  test "adds anchors to h4 tags" do
    html = render_markdown()

    assert html =~ ~s(<h4 id="how-do-i-contact-hex" class="section-heading">)
    assert html =~ ~s(<a href="#how-do-i-contact-hex" class="hover-link">)
    assert html =~ @icon
    assert html =~ "How do I contact Hex?</h4>"
  end

  test "adds a copy control that copies only the fenced source" do
    html =
      render_markdown("""
      ```elixir
      IO.puts("hi")
      ```
      """)

    {:ok, document} = Floki.parse_document(html)

    assert [button] = Floki.find(document, ~s(button[phx-hook="CopyButton"]))
    assert [target_id] = Floki.attribute(button, "data-copy-target")
    assert [target] = Floki.find(document, "##{target_id}")
    assert Floki.attribute(target, "data-value") == [~s|IO.puts("hi")\n|]

    refute html =~ "```"
    refute hd(Floki.attribute(target, "data-value")) =~ "<"
  end

  test "does not add a copy control to inline code" do
    html = render_markdown("Use `mix deps.get` to fetch deps.")
    {:ok, document} = Floki.parse_document(html)

    assert Floki.find(document, ~s(button[phx-hook="CopyButton"])) == []
    assert html =~ "<code>"
  end

  test "keeps syntax highlighting on fenced source" do
    html =
      render_markdown("""
      ```elixir
      IO.puts("hi")
      ```
      """)

    assert html =~ ~s(class="lumis")
    assert html =~ ~s(phx-hook="CopyButton")
  end

  test "does not add a copy control outside docs templates" do
    html =
      render_markdown(
        """
        ```elixir
        IO.puts("hi")
        ```
        """,
        kind: :blog
      )

    {:ok, document} = Floki.parse_document(html)

    assert Floki.find(document, ~s(button[phx-hook="CopyButton"])) == []
    assert html =~ ~s(class="lumis")
  end

  defp render_markdown(markdown \\ @markdown, opts \\ []) when is_binary(markdown) do
    kind = Keyword.get(opts, :kind, :docs)
    path = markdown_path(kind)

    File.mkdir_p!(Path.dirname(path))
    File.write!(path, markdown)

    try do
      quoted = HexpmWeb.MarkdownEngine.compile(path, nil)
      {result, _binding} = Code.eval_quoted(quoted, assigns: %{script_src_nonce: "test-nonce"})
      {:safe, html} = result
      html
    after
      File.rm(path)
    end
  end

  defp markdown_path(kind) do
    Path.join([
      @tmp_dir,
      "templates",
      template_kind_dir(kind),
      "markdown-#{System.unique_integer([:positive])}.md"
    ])
  end

  defp template_kind_dir(:docs), do: "docs"
  defp template_kind_dir(:blog), do: "blog"
end
