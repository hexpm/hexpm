defmodule HexpmWeb.Plugs.ValidateParamsTest do
  use HexpmWeb.ConnCase, async: true

  alias HexpmWeb.Plugs.ValidateParams.InvalidTextError

  describe "text Postgres can't store is refused before any query" do
    test "a NUL byte in a form body" do
      {400, headers, body} =
        assert_refused(fn ->
          post(build_conn(), "/login", %{username: "eric", password: "x", return: "/dashboard\0"})
        end)

      assert content_type(headers) =~ "text/html"
      assert body =~ "Bad request"
    end

    test "a NUL byte in a JSON body, as a value or a key" do
      for params <- [%{"name" => "a\0b"}, %{"a\0b" => "value"}, %{"nested" => [%{"a" => "b\0"}]}] do
        {400, headers, body} =
          assert_refused(fn ->
            build_conn()
            |> put_req_header("content-type", "application/json")
            |> put_req_header("accept", "application/json")
            |> post("/api/keys", JSON.encode!(params))
          end)

        assert content_type(headers) =~ "application/json"
        assert JSON.decode!(body) == %{"status" => 400, "message" => "Bad request"}
      end
    end

    test "invalid UTF-8 in an Erlang term body" do
      {400, headers, _body} =
        assert_refused(fn ->
          build_conn()
          |> put_req_header("content-type", "application/vnd.hex+erlang")
          |> put_req_header("accept", "application/vnd.hex+erlang")
          |> post("/api/keys", :erlang.term_to_binary(%{"name" => <<"a", 255, "b">>}))
        end)

      assert content_type(headers) =~ "application/vnd.hex+erlang"
    end

    test "a NUL byte or invalid UTF-8 in a path segment" do
      for path <- ["/api/packages/a%00b", "/api/packages/a%FFb", "/packages/a%00b"] do
        assert_refused(fn -> get(build_conn(), path) end)
      end
    end

    test "a NUL byte in the query string" do
      assert_refused(fn -> get(build_conn(), "/packages?search=a%00b") end)
    end

    test "routes that run no pipeline" do
      assert_refused(fn -> get(build_conn(), "/preview/a%00b/sitemap.xml") end)

      assert_refused(fn ->
        get(%{build_conn() | host: "readme.localhost"}, "/a%00b")
      end)
    end
  end

  test "valid text passes, including non-ASCII" do
    assert json_response(get(build_conn(), "/api/packages/%C3%A9cto"), 404)
  end

  # phoenix_ecto answers 400 when Postgres turns the text down too, so the
  # status alone doesn't show that no query ran.
  defp assert_refused(fun) do
    reason =
      case catch_error(fun.()) do
        %Plug.Conn.WrapperError{reason: reason} -> reason
        reason -> reason
      end

    assert %InvalidTextError{} = reason
    assert_error_sent(400, fun)
  end

  defp content_type(headers) do
    {"content-type", value} = List.keyfind(headers, "content-type", 0)
    value
  end
end
