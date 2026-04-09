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

  @path Application.compile_env(:hexpm, :tmp_dir) <> "faq.md"

  @icon HexpmWeb.ViewIcons.icon(:heroicon, :link, class: "icon-link")
        |> Phoenix.HTML.safe_to_string()

  setup do
    File.write!(@path, @markdown)
    on_exit(fn -> File.rm!(@path) end)
  end

  test "does not change h2 tags" do
    html = render_markdown()
    assert html =~ "<h2>"
  end

  test "adds anchors to h3 tags" do
    html = render_markdown()

    h3 = """
    <h3 id="contact" class="section-heading">
      <a href="#contact" class="hover-link">
        #{@icon}
      </a>
      Contact
    </h3>
    """

    assert html =~ h3
  end

  test "adds anchors to h4 tags" do
    html = render_markdown()

    h4 = """
    <h4 id="how-do-i-contact-hex" class="section-heading">
      <a href="#how-do-i-contact-hex" class="hover-link">
        #{@icon}
      </a>
      How do I contact Hex?
    </h4>
    """

    assert html =~ h4
  end

  defp render_markdown do
    quoted = HexpmWeb.MarkdownEngine.compile(@path, nil)
    {result, _binding} = Code.eval_quoted(quoted, assigns: %{script_src_nonce: "test-nonce"})
    {:safe, html} = result
    html
  end
end
