defmodule HexpmWeb.API.OAuthViewTest do
  use HexpmWeb.ConnCase, async: true

  alias HexpmWeb.API.OAuthView
  alias Hexpm.OAuth.Token

  describe "render/2 token" do
    test "creates basic response without refresh token" do
      future_time = DateTime.add(DateTime.utc_now(), 3600, :second)

      token = %Token{
        access_token: "access_token_123",
        token_type: "bearer",
        expires_at: future_time,
        scopes: ["api", "api:read"]
      }

      response = OAuthView.render("token.json", %{token: token})

      assert response.access_token == "access_token_123"
      assert response.token_type == "bearer"
      assert response.expires_in > 3590 and response.expires_in <= 3600
      assert response.scope == "api api:read"
      refute Map.has_key?(response, :refresh_token)
    end

    test "includes refresh token when present" do
      future_time = DateTime.add(DateTime.utc_now(), 3600, :second)

      token = %Token{
        access_token: "access_token_123",
        refresh_token: "refresh_token_456",
        token_type: "bearer",
        expires_at: future_time,
        scopes: ["api"]
      }

      response = OAuthView.render("token.json", %{token: token})

      assert response.access_token == "access_token_123"
      assert response.refresh_token == "refresh_token_456"
    end

    test "handles expired token gracefully" do
      past_time = DateTime.add(DateTime.utc_now(), -100, :second)

      token = %Token{
        access_token: "access_token_123",
        token_type: "bearer",
        expires_at: past_time,
        scopes: ["api"]
      }

      response = OAuthView.render("token.json", %{token: token})

      assert response.expires_in == 0
    end
  end

  describe "render/2 error" do
    test "formats error response" do
      response =
        OAuthView.render("error.json", %{
          error_type: :invalid_client,
          description: "Client authentication failed"
        })

      assert response.error == "invalid_client"
      assert response.error_description == "Client authentication failed"
    end
  end

  describe "render/2 device_authorization" do
    test "formats device authorization response" do
      expires_at = DateTime.add(DateTime.utc_now(), 600, :second)

      response =
        OAuthView.render("device_authorization.json", %{
          device_response: %{
            device_code: "device123",
            user_code: "USER-CODE",
            verification_uri: "https://hex.pm/device",
            verification_uri_complete: "https://hex.pm/device?user_code=USER-CODE",
            expires_at: expires_at,
            interval: 5
          }
        })

      assert response.device_code == "device123"
      assert response.user_code == "USER-CODE"
      assert response.verification_uri == "https://hex.pm/device"
      assert response.verification_uri_complete == "https://hex.pm/device?user_code=USER-CODE"
      assert response.expires_in >= 595 && response.expires_in <= 600
      assert response.interval == 5
    end
  end
end
