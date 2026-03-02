defmodule HexpmWeb.PolicyView do
  use HexpmWeb, :view

  def render(template, assigns) do
    content_string = render_template(template, assigns) |> Phoenix.HTML.safe_to_string()

    # Build the styled wrapper similar to blog posts
    Phoenix.HTML.raw("""
    <div class="tw:bg-grey-50 tw:py-10 tw:px-4 tw:flex-1 tw:flex tw:flex-col">
      <div class="tw:max-w-4xl tw:mx-auto tw:w-full">
        <article class="tw:bg-white tw:border tw:border-grey-200 tw:rounded-lg tw:p-6 tw:lg:p-10 tw:shadow-xs policy-content">
          <style>
            .policy-content h2 {
              font-size: 1.875rem;
              font-weight: 700;
              color: #111827;
              margin-bottom: 1.5rem;
            }
            .policy-content h3 {
              font-size: 1.5rem;
              font-weight: 700;
              color: #111827;
              margin-top: 2rem;
              margin-bottom: 1rem;
            }
            .policy-content h4 {
              font-size: 1.125rem;
              font-weight: 600;
              color: #111827;
              margin-top: 1.5rem;
              margin-bottom: 0.75rem;
            }
            .policy-content h2 > a,
            .policy-content h3 > a,
            .policy-content h4 > a {
              display: none;
              margin-left: 0.5rem;
            }
            .policy-content h2:hover > a,
            .policy-content h3:hover > a,
            .policy-content h4:hover > a {
              display: inline-block;
            }
            .policy-content h2 > a svg,
            .policy-content h3 > a svg,
            .policy-content h4 > a svg {
              width: 0.875rem;
              height: 0.875rem;
              color: #9ca3af;
            }
            .policy-content h2 > a:hover svg,
            .policy-content h3 > a:hover svg,
            .policy-content h4 > a:hover svg {
              color: #2563eb;
            }
            .policy-content p {
              font-size: 1rem;
              line-height: 1.75;
              color: #374151;
              margin-bottom: 1rem;
            }
            .policy-content a {
              color: #2563eb;
              text-decoration: underline;
              font-weight: 500;
            }
            .policy-content a:hover {
              color: #1d4ed8;
            }
            .policy-content strong {
              font-weight: 600;
              color: #111827;
            }
            .policy-content code {
              background-color: #f3f4f6;
              padding: 0.125rem 0.375rem;
              border-radius: 0.25rem;
              font-size: 0.875rem;
              font-family: ui-monospace, monospace;
              color: #1f2937;
            }
            .policy-content pre {
              background-color: #111827;
              padding: 1rem;
              border-radius: 0.5rem;
              overflow-x: auto;
              margin-bottom: 1rem;
            }
            .policy-content pre code {
              background-color: transparent;
              padding: 0;
              font-size: 0.875rem;
              color: #e5e7eb;
            }
            /* Override highlight.js background to use our dark background */
            .policy-content pre .hljs {
              background: transparent;
              color: #e5e7eb;
            }
            .policy-content ul, .policy-content ol {
              padding-left: 1.5rem;
              margin-bottom: 1rem;
              line-height: 1.75;
            }
            .policy-content ul {
              list-style-type: disc;
            }
            .policy-content ol {
              list-style-type: decimal;
            }
            .policy-content li {
              color: #374151;
              margin-bottom: 0.5rem;
            }
            .policy-content blockquote {
              border-left: 4px solid #2563eb;
              padding-left: 1rem;
              font-style: italic;
              color: #4b5563;
              margin-bottom: 1rem;
            }
          </style>
          #{content_string}
        </article>
      </div>
    </div>
    """)
  end
end
