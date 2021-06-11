defmodule Hexpm.WebAuthTest do
  use ExUnit.Case, async: true

  alias Hexpm.WebAuth

  describe "start_link/1" do
    test "correctly starts a registered GenServer", config do
      start_supervised!({WebAuth, name: config.test})

      # Verify Process is running
      assert Process.whereis(config.test)
    end
  end

  describe "get_code/2" do
    test "returns a valid response on valid scope", config do
      start_supervised!({WebAuth, name: config.test})

      for scope <- ["write", "read"] do
        response = WebAuth.get_code(config.test, %{"scope" => scope})

        assert response.device_code
        assert response.user_code
        assert response.verification_uri
        assert response.access_token_uri
        assert response.verification_expires_in
        assert response.token_access_expires_in
      end
    end

    test "returns an error on invalid scope", config do
      start_supervised!({WebAuth, name: config.test})

      assert WebAuth.get_code(config.test, %{"scope" => "foo"}) == {:error, "invalid scope"}
    end

    test "returns an error on invalid parameters", config do
      start_supervised!({WebAuth, name: config.test})

      assert WebAuth.get_code(config.test, "foo") == {:error, "invalid parameters"}
    end
  end
end
