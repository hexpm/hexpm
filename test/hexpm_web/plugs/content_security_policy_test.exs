defmodule HexpmWeb.Plugs.ContentSecurityPolicyTest do
  use HexpmWeb.ConnCase, async: true

  alias HexpmWeb.Plugs.ContentSecurityPolicy

  describe "allow_form_action/2" do
    test "adds redirect URI origin to form-action" do
      conn =
        build_conn()
        |> ContentSecurityPolicy.call(
          nonces_for: [:script_src],
          directives: %{form_action: ~w('self')}
        )
        |> ContentSecurityPolicy.allow_form_action("https://acme.hexdocs.pm/oauth/callback")

      [csp] = get_resp_header(conn, "content-security-policy")
      assert csp =~ "form-action 'self' https://acme.hexdocs.pm"
      refute csp =~ "/oauth/callback"
    end

    test "handles redirect URI with non-default port" do
      conn =
        build_conn()
        |> ContentSecurityPolicy.call(
          nonces_for: [:script_src],
          directives: %{form_action: ~w('self')}
        )
        |> ContentSecurityPolicy.allow_form_action("http://localhost:4002/oauth/callback")

      [csp] = get_resp_header(conn, "content-security-policy")
      assert csp =~ "form-action 'self' http://localhost:4002"
    end
  end
end
