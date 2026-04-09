defmodule HexpmWeb.BlogView do
  use HexpmWeb, :view

  alias Hexpm.Utils

  def render("index.html", _assigns) do
    render_template("index.html", posts: posts())
  end

  def render("index.xml", _assigns) do
    render_template("index.xml", posts: posts())
  end

  def render(other, assigns) do
    content_string = get_raw_content(other)

    # Extract metadata for the header
    {_published_rfc2822, published_human, author} = published_metadata(content_string)
    post_title = title(content_string)
    author_display = author || "Hex.pm"
    nonce = assigns[:style_src_nonce]

    # Convert icon to string
    arrow_icon =
      icon(:heroicon, "arrow-left", width: 16, height: 16) |> Phoenix.HTML.safe_to_string()

    # Build the styled wrapper with header and content
    Phoenix.HTML.raw("""
    <div class="bg-grey-50 py-10 px-4 flex-1 flex flex-col">
      <div class="max-w-4xl mx-auto w-full">
        <a href="/blog" class="inline-flex items-center gap-2 text-sm font-medium text-grey-700 hover:text-grey-900 transition-colors mb-8">
          #{arrow_icon}
          Back to Blog
        </a>
        <header class="text-center mb-8">
          <h1 class="text-2xl lg:text-4xl font-bold text-grey-900 mb-3">#{Phoenix.HTML.html_escape(post_title) |> Phoenix.HTML.safe_to_string()}</h1>
          <div class="flex items-center justify-center gap-6 text-sm text-grey-600">
            <span class="font-medium">#{published_human}</span>
            <span>by <span class="font-semibold text-grey-800">#{Phoenix.HTML.html_escape(author_display) |> Phoenix.HTML.safe_to_string()}</span></span>
          </div>
        </header>
        <article class="bg-white border border-grey-200 rounded-lg p-6 lg:p-10 shadow-xs blog-content">
          <style nonce="#{nonce}">
            .blog-content h2 {
              font-size: 1.5rem;
              font-weight: 700;
              color: #111827;
              margin-top: 2rem;
              margin-bottom: 1rem;
            }
            .blog-content h3 {
              font-size: 1.25rem;
              font-weight: 700;
              color: #111827;
              margin-top: 1.5rem;
              margin-bottom: 0.75rem;
            }
            .blog-content h4 {
              font-size: 1.125rem;
              font-weight: 600;
              color: #111827;
              margin-top: 1rem;
              margin-bottom: 0.5rem;
            }
            .blog-content h2 > a,
            .blog-content h3 > a,
            .blog-content h4 > a {
              display: none;
              margin-left: 0.5rem;
            }
            .blog-content h2:hover > a,
            .blog-content h3:hover > a,
            .blog-content h4:hover > a {
              display: inline-block;
            }
            .blog-content h2 > a svg,
            .blog-content h3 > a svg,
            .blog-content h4 > a svg {
              width: 0.875rem;
              height: 0.875rem;
              color: #9ca3af;
            }
            .blog-content h2 > a:hover svg,
            .blog-content h3 > a:hover svg,
            .blog-content h4 > a:hover svg {
              color: #2563eb;
            }
            .blog-content p {
              font-size: 1rem;
              line-height: 1.75;
              color: #374151;
              margin-bottom: 1rem;
            }
            .blog-content a {
              color: #2563eb;
              text-decoration: underline;
              font-weight: 500;
            }
            .blog-content a:hover {
              color: #1d4ed8;
            }
            .blog-content strong {
              font-weight: 600;
              color: #111827;
            }
            .blog-content code {
              background-color: #f3f4f6;
              padding: 0.125rem 0.375rem;
              border-radius: 0.25rem;
              font-size: 0.875rem;
              font-family: ui-monospace, monospace;
              color: #1f2937;
            }
            .blog-content pre {
              background-color: #111827;
              padding: 1rem;
              border-radius: 0.5rem;
              overflow-x: auto;
              margin-bottom: 1rem;
            }
            .blog-content pre code {
              background-color: transparent;
              padding: 0;
              font-size: 0.875rem;
              color: #e5e7eb;
            }
            /* Override highlight.js background to use our dark background */
            .blog-content pre .hljs {
              background: transparent;
              color: #e5e7eb;
            }
            .blog-content ul, .blog-content ol {
              padding-left: 1.5rem;
              margin-bottom: 1rem;
            }
            .blog-content ul {
              list-style-type: disc;
            }
            .blog-content ol {
              list-style-type: decimal;
            }
            .blog-content li {
              color: #374151;
              margin-bottom: 0.5rem;
            }
            .blog-content blockquote {
              border-left: 4px solid #2563eb;
              padding-left: 1rem;
              font-style: italic;
              color: #4b5563;
              margin-bottom: 1rem;
            }
            .blog-content img {
              border-radius: 0.5rem;
              box-shadow: 0 1px 2px 0 rgba(0, 0, 0, 0.05);
              margin: 1rem auto;
              max-width: 100%;
              display: block;
            }
            .blog-content .subtitle {
              color: #6b7280;
              font-size: 0.875rem;
              margin-bottom: 1.5rem;
            }
          </style>
          #{strip_header(content_string)}
        </article>
      </div>
    </div>
    """)
  end

  # Get raw template content without wrapper (used by both render and posts)
  defp get_raw_content(template) do
    # Ensure template has .html suffix for render_template
    template_name =
      if String.ends_with?(template, ".html") do
        template
      else
        "#{template}.html"
      end

    render_template(template_name, %{})
    |> Phoenix.HTML.safe_to_string()
  end

  defp posts() do
    Enum.map(HexpmWeb.Blog.Posts.all_templates(), fn {slug, template} ->
      content = get_raw_content(template)
      {published_rfc2822, published_human, author} = published_metadata(content)

      %{
        slug: slug,
        title: title(content),
        subtitle: subtitle(content),
        paragraph: first_paragraph(content),
        published: published_rfc2822,
        published_date: published_human,
        author: author
      }
    end)
  end

  defp first_paragraph(content) do
    regex_run(~r[<p>(.*)</p>]sU, content)
  end

  defp title(content) do
    regex_run(~r[<h2>(.*)</h2>]sU, content)
  end

  defp subtitle(content) do
    regex_run(~r[<div class="subtitle">(.*)</div>]sU, content)
  end

  defp published_metadata(content) do
    # Extract datetime from <time> tag
    iso_datetime =
      ~r[<time datetime="(.+)">(.+)</time>]sU
      |> regex_run(content)

    {:ok, datetime, _utc_offset} = DateTime.from_iso8601(iso_datetime)

    # Extract author from subtitle - look for "by Author Name" pattern
    # The subtitle format is: <time>...</time> · by Author Name
    author =
      case Regex.run(~r/·\s*by\s+([^<]+)<\/div>/, content) do
        [_, name] -> String.trim(name)
        _ -> nil
      end

    {
      Utils.datetime_to_rfc2822(datetime),
      Calendar.strftime(datetime, "%d %b %Y"),
      author
    }
  end

  defp strip_header(content) do
    content
    |> String.replace(~r/<h2>.*<\/h2>\s*/sU, "", global: false)
    |> String.replace(~r/<div class="subtitle">.*<\/div>\s*/sU, "", global: false)
  end

  defp regex_run(regex, string) do
    regex
    |> Regex.run(string)
    |> Enum.at(1)
    |> String.trim()
  end
end
