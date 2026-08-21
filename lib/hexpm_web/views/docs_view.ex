defmodule HexpmWeb.DocsView do
  use HexpmWeb, :view
  alias HexpmWeb.DocsView

  defp docs_sections() do
    [
      {"Mix",
       [
         %{view: :usage, label: "Usage", href: ~p"/docs/usage"},
         %{view: :publish, label: "Publishing packages", href: ~p"/docs/publish"},
         %{view: :private, label: "Private packages", href: ~p"/docs/private"},
         %{
           view: :dependency_policies,
           label: "Dependency policies",
           href: ~p"/docs/dependency-policies"
         },
         %{external: true, label: "Tasks", href: "https://hexdocs.pm/hex"}
       ]},
      {"Rebar",
       [
         %{view: :rebar3_usage, label: "Usage", href: ~p"/docs/rebar3-usage"},
         %{view: :rebar3_publish, label: "Publishing packages", href: ~p"/docs/rebar3-publish"},
         %{view: :rebar3_private, label: "Private packages", href: ~p"/docs/rebar3-private"},
         %{
           external: true,
           label: "Tasks",
           href: "https://rebar3.org/docs/package_management/hex_package_management/"
         }
       ]},
      {"Gleam",
       [
         %{view: :gleam_usage, label: "Usage", href: ~p"/docs/gleam-usage"},
         %{external: true, label: "Tasks", href: "https://gleam.run/command-line-reference/"}
       ]},
      {"Hex",
       organization_sso_link() ++
         [
           %{view: :faq, label: "FAQ", href: ~p"/docs/faq"},
           %{view: :self_hosting, label: "Self-hosting", href: ~p"/docs/self-hosting"},
           %{view: :mirrors, label: "Mirrors", href: ~p"/docs/mirrors"},
           %{view: :public_keys, label: "Public keys", href: ~p"/docs/public-keys"}
         ]}
    ]
  end

  defp organization_sso_link() do
    if Hexpm.Accounts.SSO.available?(),
      do: [
        %{view: :organization_sso, label: "Organization SSO", href: ~p"/docs/organization-sso"}
      ],
      else: []
  end

  defp docs_link_class(true),
    do:
      "block px-3 py-1.5 text-sm rounded transition-colors bg-blue-50 dark:bg-blue-900/30 text-blue-600 dark:text-blue-200 font-medium"

  defp docs_link_class(false),
    do:
      "block px-3 py-1.5 text-sm rounded transition-colors text-grey-700 dark:text-grey-200 hover:bg-grey-50 dark:hover:bg-grey-700"
end
