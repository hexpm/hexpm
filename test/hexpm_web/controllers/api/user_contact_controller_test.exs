defmodule HexpmWeb.API.UserContactControllerTest do
  use HexpmWeb.ConnCase, async: true

  @signing_key File.read!("test/fixtures/varsel_private.pem")

  describe "GET /api/users/:name/contact" do
    test "returns the name, canonical username and primary email address" do
      user = insert(:user, username: "contact_person", full_name: "Contact Person")
      [email] = user.emails

      conn = lookup("Contact_Person")

      assert json_response(conn, 200) == %{
               "username" => "contact_person",
               "name" => "Contact Person",
               "email" => email.email
             }

      assert get_resp_header(conn, "cache-control") == ["private, max-age=60"]
    end

    test "falls back to the username when the full name is blank" do
      user = insert(:user, full_name: " ")

      assert json_response(lookup(user.username), 200)["name"] == user.username
    end

    test "omits the email when the primary address is unverified" do
      user = insert(:user, emails: [build(:email, verified: false)])

      body = json_response(lookup(user.username), 200)
      assert body["username"] == user.username
      refute Map.has_key?(body, "email")
    end

    test "finds the account by a verified secondary address and returns the primary one" do
      primary = build(:email, email: "primary@example.com")
      secondary = build(:email, email: "secondary@example.com", primary: false, public: false)
      user = insert(:user, emails: [primary, secondary])

      assert json_response(lookup("Secondary@example.com"), 200) == %{
               "username" => user.username,
               "name" => user.full_name,
               "email" => "primary@example.com"
             }
    end

    test "does not find an account by an unverified address" do
      unverified =
        build(:email,
          email: "unverified@example.com",
          primary: false,
          public: false,
          verified: false
        )

      insert(:user, emails: [build(:email), unverified])

      assert json_response(lookup("unverified@example.com"), 404)
    end

    test "returns 404 for an unknown username" do
      assert json_response(lookup("nobody"), 404)
    end

    test "returns 404 for an organization account" do
      organization = insert(:organization)

      assert json_response(lookup(organization.name), 404)
    end

    test "returns 404 for a service account" do
      user = insert(:user, service: true)

      assert json_response(lookup(user.username), 404)
    end

    test "returns 404 for a deactivated account" do
      user = insert(:user, deactivated_at: DateTime.utc_now())

      assert json_response(lookup(user.username), 404)
    end

    test "accepts an audience list that names hex.pm" do
      user = insert(:user)
      token = sign(claims(%{"aud" => ["https://example.com", HexpmWeb.Endpoint.url()]}))

      assert json_response(lookup(user.username, token), 200)
    end
  end

  describe "GET /api/users/:name/contact authentication" do
    setup do
      %{user: insert(:user)}
    end

    test "refuses a request without a bearer token", %{user: user} do
      conn = get(build_conn(), "/api/users/#{user.username}/contact")
      assert_refused(conn)

      conn =
        build_conn()
        |> put_req_header("authorization", "Basic #{Base.encode64("varsel:secret")}")
        |> get("/api/users/#{user.username}/contact")

      assert_refused(conn)
    end

    test "refuses a token that is not a JWT", %{user: user} do
      assert_refused(lookup(user.username, "not-a-jwt"))
      assert_refused(lookup(user.username, "a.b.c"))
    end

    test "refuses any algorithm other than ES256", %{user: user} do
      signer = Joken.Signer.create("HS256", "secret", %{"kid" => "varsel-test"})

      assert_refused(lookup(user.username, sign(claims(), signer)))
    end

    test "refuses an unsigned token claiming alg none", %{user: user} do
      header = %{"alg" => "none", "typ" => "JWT", "kid" => "varsel-test"}
      encode = &Base.url_encode64(JSON.encode!(&1), padding: false)

      assert_refused(lookup(user.username, "#{encode.(header)}.#{encode.(claims())}."))
    end

    test "refuses an unknown key id", %{user: user} do
      signer = signer("varsel-prod")

      assert_refused(lookup(user.username, sign(claims(), signer)))
    end

    test "refuses a signature from another key", %{user: user} do
      pem = Application.fetch_env!(:hexpm, :jwt_signing_key)
      signer = Joken.Signer.create("ES256", %{"pem" => pem}, %{"kid" => "varsel-test"})

      assert_refused(lookup(user.username, sign(claims(), signer)))
    end

    test "refuses the wrong issuer, subject or audience", %{user: user} do
      assert_refused(lookup(user.username, sign(claims(%{"iss" => "hexpm"}))))
      assert_refused(lookup(user.username, sign(claims(%{"sub" => "hexpm"}))))
      assert_refused(lookup(user.username, sign(claims(%{"aud" => "https://example.com"}))))
      assert_refused(lookup(user.username, sign(claims(%{"aud" => ["https://example.com"]}))))
    end

    test "refuses a token outside its validity window", %{user: user} do
      now = System.system_time(:second)

      assert_refused(lookup(user.username, sign(Map.delete(claims(), "exp"))))
      assert_refused(lookup(user.username, sign(claims(%{"exp" => now}))))
      assert_refused(lookup(user.username, sign(claims(%{"nbf" => now + 60}))))
    end

    test "refuses a token that lives longer than five minutes", %{user: user} do
      now = System.system_time(:second)
      token = sign(claims(%{"iat" => now - 240, "nbf" => now - 240, "exp" => now + 120}))

      assert_refused(lookup(user.username, token))
    end

    test "refuses a token without a token id", %{user: user} do
      assert_refused(lookup(user.username, sign(Map.delete(claims(), "jti"))))
    end

    test "refuses a replayed token", %{user: user} do
      token = sign(claims())

      assert json_response(lookup(user.username, token), 200)
      assert_refused(lookup(user.username, token))
    end
  end

  defp lookup(name, token \\ sign(claims())) do
    build_conn()
    |> put_req_header("authorization", "Bearer #{token}")
    |> get("/api/users/#{name}/contact")
  end

  defp assert_refused(conn) do
    assert json_response(conn, 401)["message"] == "invalid token"
    assert get_resp_header(conn, "www-authenticate") == [~s(Bearer error="invalid_token")]
  end

  defp claims(overrides \\ %{}) do
    now = System.system_time(:second)

    Map.merge(
      %{
        "iss" => "varsel",
        "sub" => "varsel",
        "aud" => HexpmWeb.Endpoint.url(),
        "iat" => now,
        "nbf" => now - 5,
        "exp" => now + 60,
        "jti" => Ecto.UUID.generate()
      },
      overrides
    )
  end

  defp signer(kid) do
    Joken.Signer.create("ES256", %{"pem" => @signing_key}, %{"kid" => kid})
  end

  defp sign(claims, signer \\ signer("varsel-test")) do
    {:ok, token} = Joken.Signer.sign(claims, signer)
    token
  end
end
