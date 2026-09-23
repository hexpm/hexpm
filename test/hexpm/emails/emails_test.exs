defmodule Hexpm.EmailsTest do
  use Hexpm.DataCase, async: false

  alias Hexpm.Accounts.Organization
  alias Hexpm.Accounts.OrganizationInvitation
  alias Hexpm.Emails
  alias HexpmWeb.EmailView.Common

  defp package_published_email() do
    Emails.package_published([build(:user)], build(:user), "cowboy", "2.16.1")
  end

  describe "type" do
    test "names the builder that produced the email" do
      assert package_published_email().private.type == "package_published"

      assert Emails.announcement("bob@example.com", "Subject", "Body").private.type ==
               "announcement"
    end
  end

  describe "html layout" do
    test "header does not rely on flexbox" do
      refute package_published_email().html_body =~ "display: flex"
    end

    test "header wordmark is a link with explicit white color and no underline" do
      assert [wordmark] =
               package_published_email().html_body
               |> LazyHTML.from_document()
               |> LazyHTML.query("a")
               |> Enum.filter(&(&1 |> LazyHTML.text() |> String.trim() == "Hex"))

      assert [{"a", attrs, _children}] = LazyHTML.to_tree(wordmark)
      attrs = Map.new(attrs)
      assert attrs["href"] == Application.fetch_env!(:hexpm, :email_base_url) <> "/"
      assert attrs["style"] =~ "color: #ffffff"
      assert attrs["style"] =~ "text-decoration: none"
    end

    test "logo is a png image" do
      assert [src] =
               package_published_email().html_body
               |> LazyHTML.from_document()
               |> LazyHTML.query("img")
               |> LazyHTML.attribute("src")

      assert src =~ "hex-full.png"
    end

    test "does not include a signature footer" do
      refute package_published_email().html_body =~ "Hex.pm"
    end

    test "renders without endpoint runtime state" do
      endpoint_key = {Phoenix.Endpoint, HexpmWeb.Endpoint}
      endpoint_state = :persistent_term.get(endpoint_key)
      :persistent_term.erase(endpoint_key)

      on_exit(fn -> :persistent_term.put(endpoint_key, endpoint_state) end)

      email = Emails.password_reset_request(build(:user), %{key: "abc"})

      assert email.html_body =~ "http://localhost:5000/images/hex-full.png"
      assert email.html_body =~ "http://localhost:5000/password/new"
    end
  end

  describe "code blocks" do
    test "render inside table cells instead of divs" do
      emails = [
        package_published_email(),
        Emails.organization_invite(%Organization{name: "acme"}, build(:user)),
        Emails.password_reset_request(build(:user), %{key: "abc"}),
        Emails.security_password_reset(build(:user), %{key: "abc"}),
        Emails.typosquat_candidates([["foo", "phoo", 1]], 2)
      ]

      for email <- emails do
        refute email.html_body =~ "<div"
      end
    end
  end

  describe "security_password_reset/2" do
    test "matches the styled email design" do
      email = Emails.security_password_reset(build(:user), %{key: "abc"})
      # HTML5 parsing closes paragraphs before pre elements, so check the source.
      refute email.html_body =~ ~r/<p\b[^>]*>(?:(?!<\/p\s*>).)*<pre\b/is
      document = LazyHTML.from_document(email.html_body)

      assert [_title] = LazyHTML.query(document, "h1") |> Enum.to_list()

      assert Enum.any?(LazyHTML.query(document, "a") |> LazyHTML.to_tree(), fn {"a", attrs,
                                                                                _children} ->
               (Map.new(attrs)["href"] || "") =~ "/password/new"
             end)
    end
  end

  # Recipient selection lives in Hexpm.Accounts.SSO, which passes an already
  # filtered list; these cover the rendering only.
  describe "organization 2FA notices" do
    defp tfa_organization() do
      %Organization{name: "acme", tfa_required_at: ~U[2026-09-29 01:04:00.000000Z]}
    end

    defp tfa_email(stage, suspended \\ []) do
      Emails.organization_tfa(tfa_organization(), stage, ["member@example.com"], suspended)
    end

    test "notices before the deadline say what happens at the deadline" do
      for {stage, subject} <- [
            {"scheduled", "Hex.pm - acme will require two-factor authentication"},
            {"seven_days", "Hex.pm - acme requires two-factor authentication in 7 days"},
            {"one_day", "Hex.pm - acme requires two-factor authentication within a day"}
          ] do
        email = tfa_email(stage)
        assert email.subject == subject

        assert email.text_body =~
                 "requires two-factor authentication from September 29, 2026 at 01:04 UTC."

        assert email.text_body =~ "before then to keep access"
        assert email.html_body =~ "/dashboard/security"
        refute email.text_body =~ "work again"
        refute email.text_body =~ "invitation"
      end
    end

    test "the suspension notice says access returns once 2FA is enabled" do
      email = tfa_email("suspended")
      assert email.subject == "Hex.pm - Your access to acme is suspended until you enable 2FA"
      assert email.text_body =~ "suspended until you enable 2FA at "
      assert email.text_body =~ "work again as soon as it's enabled"
    end

    test "the administrator summary lists suspended members instead of asking to enable 2FA" do
      email = tfa_email("summary", ["alice", "bob"])
      assert email.subject == "Hex.pm - acme now requires two-factor authentication"

      assert email.text_body =~
               "Members suspended because they haven't enabled 2FA: alice, bob."

      assert email.text_body =~ "/dashboard/orgs/acme/members"
      refute email.text_body =~ "/dashboard/security"

      assert tfa_email("summary").text_body =~
               "Every member has 2FA enabled, so no one is suspended."
    end
  end

  describe "SSO security notifications" do
    test "link and unlink notifications address the recipients they are given" do
      for email <- [
            Emails.sso_identity_linked("acme", "eric", ["primary@example.com"]),
            Emails.sso_identity_unlinked(
              "acme",
              "eric",
              "alice",
              true,
              "https://hex.pm/sso/org/acme",
              ["primary@example.com"]
            )
          ] do
        assert Enum.map(email.to, &elem(&1, 1)) == ["primary@example.com"]
        assert email.text_body =~ "acme"
        assert email.text_body =~ "eric"
      end
    end

    test "unlink says who disconnected the account and how to connect it again" do
      email =
        Emails.sso_identity_unlinked(
          "acme",
          "eric",
          "alice",
          true,
          "https://hex.pm/sso/org/acme",
          ["primary@example.com"]
        )

      for body <- [email.html_body, email.text_body] do
        assert body =~ "alice, an administrator of the acme organization, disconnected"
        assert body =~ "https://hex.pm/sso/org/acme"
        assert body =~ "ask an administrator of the acme organization"
        refute body =~ "Conventional Hex.pm login"
        refute body =~ "contact support"
      end

      assert email.text_body =~ "you can't reach it until you connect your account again"
    end

    test "unlink by the member themself asks nobody else about it" do
      email =
        Emails.sso_identity_unlinked(
          "acme",
          "eric",
          "eric",
          false,
          "https://hex.pm/sso/org/acme",
          ["primary@example.com"]
        )

      assert email.text_body =~ "You disconnected your Hex.pm account"
      assert email.text_body =~ "your access to it hasn't changed"
      refute email.text_body =~ "ask an administrator"
    end

    test "email mismatch identifies the provider address" do
      email =
        Emails.sso_email_mismatch(
          "acme",
          "eric",
          ["primary@example.com"],
          "person@idp.example"
        )

      assert email.text_body =~ "person@idp.example"
      assert email.text_body =~ "no account email was changed"
    end
  end

  describe "sso_break_glass/4" do
    test "says what was reached in words" do
      email = Emails.sso_break_glass("acme", "alice", "delete", ["admin@example.com"])

      for body <- [email.html_body, email.text_body] do
        assert body =~
                 "alice reached the acme organization on Hex.pm without a current single " <>
                   "sign-on session, to delete the identity provider connection."

        refute body =~ "as seen"
        refute body =~ "not one of your administrators"
      end
    end

    test "leaves out a screen it has no words for" do
      email = Emails.sso_break_glass("acme", "alice", "somewhere", ["admin@example.com"])

      assert email.text_body =~
               "alice reached the acme organization on Hex.pm without a current single " <>
                 "sign-on session.\n"

      refute email.text_body =~ "somewhere"
    end
  end

  describe "sso_enforcement_pending/5" do
    defp pending_email(notice) do
      Emails.sso_enforcement_pending(
        "acme",
        ~U[2026-10-01 00:00:00Z],
        Map.merge(
          %{
            linked?: false,
            session_lifetime: 86_400,
            keys: %{revoked: [], trimmed: [], blocked: []}
          },
          notice
        ),
        "https://hex.pm/sso/org/acme",
        ["member@example.com"]
      )
    end

    test "says what changes after the date for a linked member" do
      email = pending_email(%{linked?: true, session_lifetime: 28_800})

      for body <- [email.html_body, email.text_body] do
        assert body =~ "October 1, 2026"
        assert body =~ "again every 8 hours"
        assert body =~ "public packages you can only manage because the organization owns them"
        refute body =~ "nothing about your day changes"
        refute body =~ "does not affect your Hex account"
        refute body =~ "https://hex.pm/sso/org/acme"
      end
    end

    test "links an unlinked member to the provider" do
      email = pending_email(%{})

      for body <- [email.html_body, email.text_body] do
        assert body =~ "https://hex.pm/sso/org/acme"
      end

      assert email.text_body =~ "isn't connected to that provider yet"
    end

    test "names the personal keys the date strips or refuses" do
      email =
        pending_email(%{
          keys: %{revoked: ["laptop"], trimmed: ["desk", "ci"], blocked: ["everything"]}
        })

      for body <- [email.html_body, email.text_body] do
        assert body =~ "Your key laptop carries nothing but access to this organization, so it"
        assert body =~ "Your keys desk, ci will lose their permissions for this organization"
        assert body =~ "Your key everything reaches this organization through wider permissions"
        assert body =~ "organization key"
      end
    end

    test "says nothing about keys a member does not hold" do
      refute pending_email(%{}).text_body =~ "personal API keys"
    end
  end

  describe "sso_enforcement_started/4" do
    test "says the requirement applies now and how to regain access" do
      email =
        Emails.sso_enforcement_started(
          "acme",
          3_600,
          "https://hex.pm/sso/org/acme",
          ["member@example.com"]
        )

      assert email.subject == "Hex.pm - acme now requires single sign-on"

      for body <- [email.html_body, email.text_body] do
        assert body =~ "now requires you to sign in through its identity provider"
        assert body =~ "https://hex.pm/sso/org/acme"
        assert body =~ "again every hour"
        refute body =~ "From "
      end
    end
  end

  describe "sso_seats/4" do
    test "tells a login apart from provisioning" do
      login = Emails.sso_seats("acme", "seats_exhausted", "login", ["admin@example.com"])
      scim = Emails.sso_seats("acme", "seats_exhausted", "scim", ["admin@example.com"])

      assert login.text_body =~ "Someone signed in to the acme organization"
      assert login.text_body =~ "ask them to sign in again"

      assert scim.text_body =~ "Your identity provider asked through SCIM provisioning"
      refute scim.text_body =~ "Someone signed in"
      refute scim.text_body =~ "sign in again"
    end

    test "says when a failed purchase is tried again" do
      email = Emails.sso_seats("acme", "expansion_failed", "login", ["admin@example.com"])

      assert email.text_body =~ "For an hour after a failed purchase"
      refute email.text_body =~ "without retrying the purchase"
    end

    test "does not call an unreadable seat count a full organization" do
      email = Emails.sso_seats("acme", "seat_limit_unknown", "login", ["admin@example.com"])

      assert email.subject == "Hex.pm - acme seat count could not be read"
      assert email.text_body =~ "couldn't read how many seats the organization has paid for"
      refute email.text_body =~ "no seats left"
    end
  end

  describe "sso_keys_refused/5" do
    test "asks for nothing that cannot be done with a revoked key" do
      email = Emails.sso_keys_refused("acme", ["laptop"], [], [], ["primary@example.com"])

      for body <- [email.html_body, email.text_body] do
        assert body =~ "The key laptop carried nothing else, so it has been revoked."
        # Revoked keys are not listed on the dashboard.
        refute body =~ "dashboard"
      end
    end

    test "tells the owner to remove a key mix stored for the organization" do
      for email <- [
            Emails.sso_keys_refused("acme", ["laptop"], [], [], ["primary@example.com"]),
            Emails.sso_keys_refused("acme", [], [], ["laptop"], ["primary@example.com"])
          ],
          body <- [email.html_body, email.text_body] do
        assert body =~ "mix hex.user auth"
        assert body =~ "Run mix hex.organization deauth acme on that machine"
      end
    end
  end

  describe "secrets detected" do
    defp secrets_detected_email(findings) do
      Emails.secrets_detected([build(:user)], "cowboy", "2.16.1", findings)
    end

    defp finding(attrs \\ []) do
      struct(
        %Hexpm.SecretScan.Finding{
          rule: "aws-access-token",
          file_path: "config/prod.exs",
          line: 12,
          byte_offset: 340,
          fingerprint: <<0xAA>>,
          preview: "AKIA************WXYZ"
        },
        attrs
      )
    end

    test "names the package, the location and the masked value" do
      email = secrets_detected_email([finding()])

      assert email.subject == "Hex.pm - Possible credentials found in cowboy v2.16.1"

      for body <- [email.html_body, email.text_body] do
        assert body =~ "cowboy v2.16.1"
        assert body =~ "config/prod.exs:12"
        assert body =~ "aws-access-token"
        assert body =~ "AKIA************WXYZ"
        assert body =~ "revoke and reissue"
      end
    end

    test "lists every finding" do
      findings = [
        finding(),
        finding(
          rule: "github-pat",
          file_path: ".env",
          line: 3,
          fingerprint: <<0xBB>>,
          preview: "ghp_************OU7Q"
        )
      ]

      for body <- [
            secrets_detected_email(findings).html_body,
            secrets_detected_email(findings).text_body
          ] do
        assert body =~ "config/prod.exs:12"
        assert body =~ ".env:3"
        assert body =~ "2 values"
      end
    end

    test "one credential in several files is one entry with every place listed" do
      findings = [
        finding(),
        finding(file_path: "lib/app.ex", line: 4),
        finding(file_path: "test/support.ex", line: 9)
      ]

      for body <- [
            secrets_detected_email(findings).html_body,
            secrets_detected_email(findings).text_body
          ] do
        assert body =~ "a value that looks like"
        assert body =~ "config/prod.exs:12"
        assert body =~ "lib/app.ex:4"
        assert body =~ "test/support.ex:9"
        # The rule and the masked value belong to the credential, not to each
        # place it turned up in.
        assert body |> String.split("AKIA************WXYZ") |> length() == 2
      end
    end

    test "reads as singular for one finding" do
      email = secrets_detected_email([finding()])
      assert email.text_body =~ "a value that looks like"
      refute email.text_body =~ "1 values"
    end

    test "falls back to a byte offset when a file has no usable line" do
      email = secrets_detected_email([finding(line: 0)])
      assert email.text_body =~ "config/prod.exs@340"
    end

    test "says hex.pm did nothing else and stores nothing" do
      email = secrets_detected_email([finding()])

      assert email.text_body =~ "taken no other action"
      assert email.text_body =~ "never the value itself"
    end
  end

  describe "links" do
    test "Common.link emits anchors with explicit styles" do
      html = Common.link("https://example.com", "click", :html)

      assert html =~ ~s(href="https://example.com")
      assert html =~ "color: #0f59d8"
      assert html =~ "text-decoration: none"
    end

    test "helpers returning html render as html instead of escaped text" do
      emails = [
        Emails.password_reset_request(build(:user), %{key: "abc"}),
        Emails.security_password_reset(build(:user), %{key: "abc"})
      ]

      for email <- emails do
        refute email.html_body =~ "&lt;a"
      end
    end

    test "action urls are shown once" do
      user = build(:user)

      invitation = %OrganizationInvitation{
        email: "invitee@example.com",
        role: "read",
        raw_token: "abc",
        expires_at: ~U[2026-10-01 00:00:00.000000Z],
        organization: %Organization{name: "acme"}
      }

      emails = [
        {Emails.verification(user, build(:email, verification_key: "abc")), "/email/verify?"},
        {Emails.organization_invitation(invitation), "/invites?"},
        {Emails.password_reset_request(user, %{key: "abc"}), "/password/new?"},
        {Emails.security_password_reset(user, %{key: "abc"}), "/password/new?"}
      ]

      for {email, path} <- emails do
        text = email.html_body |> LazyHTML.from_document() |> LazyHTML.text()
        assert text |> String.split(path) |> length() == 2
      end
    end
  end
end
