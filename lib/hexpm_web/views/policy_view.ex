defmodule HexpmWeb.PolicyView do
  use HexpmWeb, :view

  def render(template, assigns) do
    content_string = render_template(template, assigns) |> Phoenix.HTML.safe_to_string()
    nonce = assigns[:style_src_nonce]

    Phoenix.HTML.raw("""
    <div class="bg-grey-50 dark:bg-grey-950 py-10 px-4 flex-1 flex flex-col">
      <div class="max-w-4xl mx-auto w-full">
        <article class="bg-white dark:bg-grey-800 border border-grey-200 dark:border-grey-700 rounded-lg p-6 lg:p-10 shadow-xs policy-content">
          <style nonce="#{nonce}">
            .policy-content h2 {
              font-size: 1.875rem;
              font-weight: 700;
              color: var(--color-grey-900);
              margin-bottom: 1.5rem;
            }
            .policy-content h3 {
              font-size: 1.5rem;
              font-weight: 700;
              color: var(--color-grey-900);
              margin-top: 2rem;
              margin-bottom: 1rem;
            }
            .policy-content h4 {
              font-size: 1.125rem;
              font-weight: 600;
              color: var(--color-grey-900);
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
              color: var(--color-grey-300);
            }
            .policy-content h2 > a:hover svg,
            .policy-content h3 > a:hover svg,
            .policy-content h4 > a:hover svg {
              color: var(--color-blue-600);
            }
            .policy-content p {
              font-size: 1rem;
              line-height: 1.75;
              color: var(--color-grey-600);
              margin-bottom: 1rem;
            }
            .policy-content a {
              color: var(--color-blue-600);
              text-decoration: underline;
              font-weight: 500;
            }
            .policy-content a:hover {
              color: var(--color-blue-700);
            }
            .policy-content strong {
              font-weight: 600;
              color: var(--color-grey-900);
            }
            .policy-content code:not(pre code) {
              background-color: var(--color-grey-50);
              padding: 0.125rem 0.375rem;
              border-radius: 0.25rem;
              font-size: 0.875rem;
              font-family: ui-monospace, monospace;
              color: var(--color-grey-800);
            }
            .policy-content pre {
              background-color: var(--color-grey-900);
              padding: 1rem;
              border-radius: 0.5rem;
              overflow-x: auto;
              margin-bottom: 1rem;
            }
            .policy-content pre code {
              background-color: transparent;
              padding: 0;
              font-size: 0.875rem;
              color: var(--color-grey-100);
            }
            /* Override highlight.js background to use our dark background */
            .policy-content pre .hljs {
              background: transparent;
              color: var(--color-grey-100);
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
              color: var(--color-grey-600);
              margin-bottom: 0.5rem;
            }
            .policy-content blockquote {
              border-left: 4px solid var(--color-blue-600);
              padding-left: 1rem;
              font-style: italic;
              color: var(--color-grey-600);
              margin-bottom: 1rem;
            }
            html[data-theme="dark"] .policy-content h2,
            html[data-theme="dark"] .policy-content h3,
            html[data-theme="dark"] .policy-content h4,
            html[data-theme="dark"] .policy-content strong {
              color: white;
            }
            html[data-theme="dark"] .policy-content h2 > a svg,
            html[data-theme="dark"] .policy-content h3 > a svg,
            html[data-theme="dark"] .policy-content h4 > a svg {
              color: var(--color-grey-300);
            }
            html[data-theme="dark"] .policy-content h2 > a:hover svg,
            html[data-theme="dark"] .policy-content h3 > a:hover svg,
            html[data-theme="dark"] .policy-content h4 > a:hover svg {
              color: var(--color-blue-200);
            }
            html[data-theme="dark"] .policy-content p {
              color: var(--color-grey-200);
            }
            html[data-theme="dark"] .policy-content li {
              color: var(--color-grey-200);
            }
            html[data-theme="dark"] .policy-content a {
              color: var(--color-blue-300);
            }
            html[data-theme="dark"] .policy-content a:hover {
              color: var(--color-blue-200);
            }
            html[data-theme="dark"] .policy-content code:not(pre code) {
              background-color: var(--color-grey-700);
              color: var(--color-grey-100);
            }
            html[data-theme="dark"] .policy-content pre {
              background-color: var(--color-grey-900);
            }
            html[data-theme="dark"] .policy-content pre code,
            html[data-theme="dark"] .policy-content pre .hljs {
              color: var(--color-grey-100);
            }
            html[data-theme="dark"] .policy-content blockquote {
              border-left-color: var(--color-blue-300);
              color: var(--color-grey-300);
            }
            html[data-theme="dark"] .policy-content dt {
              color: var(--color-grey-100);
            }
            html[data-theme="dark"] .policy-content dd {
              color: var(--color-grey-300);
            }
          </style>
          #{content_string}
        </article>
      </div>
    </div>
    """)
  end
end
