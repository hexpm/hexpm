defmodule HexpmWeb.EmergencyPublishingBannerTest do
  use HexpmWeb.ConnCase

  test "normal package approval doesn't display the emergency banner" do
    app_env(:hexpm, :force_publish_approval, false)
    put_feature_flag(:workload_identity, mode: :enabled)

    for path <- ["/", "/login", "/docs/publish"] do
      document = build_conn() |> get(path) |> html_response(200) |> LazyHTML.from_document()
      assert Enum.empty?(LazyHTML.query(document, "#emergency-publishing-banner"))
    end
  end

  test "emergency mode explains the active requirements above the website" do
    app_env(:hexpm, :force_publish_approval, true)
    put_feature_flag(:workload_identity, mode: :off)

    for path <- ["/", "/login", "/docs/publish"] do
      document = build_conn() |> get(path) |> html_response(200) |> LazyHTML.from_document()

      assert [banner, _header] =
               Enum.to_list(
                 LazyHTML.query(document, "#emergency-publishing-banner, #main-navbar")
               )

      assert LazyHTML.attribute(banner, "id") == ["emergency-publishing-banner"]
      text = banner |> LazyHTML.text() |> String.replace(~r/\s+/, " ")
      assert text =~ "Emergency publishing mode is active."
      assert text =~ "Automated publishes require approval with fresh 2FA."
    end
  end

  test "the banner's guide is available with Workload Identity disabled" do
    app_env(:hexpm, :force_publish_approval, true)
    put_feature_flag(:workload_identity, mode: :off)
    document = build_conn() |> get("/login") |> html_response(200) |> LazyHTML.from_document()

    assert [href] =
             document
             |> LazyHTML.query("#emergency-publishing-banner a")
             |> LazyHTML.attribute("href")

    [path, anchor] = String.split(href, "#")
    document = build_conn() |> get(path) |> html_response(200) |> LazyHTML.from_document()
    assert [_heading] = Enum.to_list(LazyHTML.query(document, ".docs-content ##{anchor}"))
    text = LazyHTML.text(document)
    assert text =~ "releases and documentation in both public and private repositories"
    assert text =~ "All API keys, organization-key OAuth exchanges and workload identities"
    assert text =~ "Automated reverts are blocked."
    assert text =~ "Human OAuth publishing with an OTP remains direct."

    assert text =~
             "Adding owners and organization members works as it does outside emergency mode."

    assert [_anchor, heading | _] =
             document
             |> LazyHTML.query(".docs-content a[id=secret-scanning], .docs-content h3")
             |> Enum.drop_while(&(LazyHTML.attribute(&1, "id") != ["secret-scanning"]))

    assert heading |> LazyHTML.text() |> String.trim() == "Secret scanning"
  end

  test "emergency and read-only notices appear together before navigation" do
    app_env(:hexpm, :force_publish_approval, true)
    app_env(:hexpm, :read_only_mode, true)
    document = build_conn() |> get("/login") |> html_response(200) |> LazyHTML.from_document()

    assert [read_only, emergency, _header] =
             Enum.to_list(
               LazyHTML.query(
                 document,
                 ".read-only-mode, .emergency-publishing-mode, #main-navbar"
               )
             )

    assert LazyHTML.text(read_only) =~ "read only mode due to maintenance"
    assert LazyHTML.attribute(emergency, "id") == ["emergency-publishing-banner"]
    assert LazyHTML.text(emergency) =~ "Automated publishes require approval with fresh 2FA."
  end
end
