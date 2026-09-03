defmodule Hexpm.Security.AdvisoryTest do
  use Hexpm.DataCase, async: true

  alias Hexpm.Security.{Advisory, AdvisoryReference}

  describe "Advisory.changeset/2" do
    test "bounds the summary in codepoints" do
      attrs = %{
        id: "GHSA-xxxx-xxxx-xxxx",
        published_at: ~U[2024-04-03 16:46:30Z],
        modified_at: ~U[2024-04-05 01:28:39Z]
      }

      assert Advisory.changeset(%Advisory{}, Map.put(attrs, :summary, codepoints_string(255))).valid?

      changeset =
        Advisory.changeset(%Advisory{}, Map.put(attrs, :summary, codepoints_string(256)))

      assert errors_on(changeset).summary == "should be at most 255 character(s)"
    end
  end

  describe "AdvisoryReference.changeset/2" do
    test "bounds the url in bytes" do
      prefix = "https://example.com/"
      at_cap = prefix <> combining_string(2000 - byte_size(prefix))

      assert AdvisoryReference.changeset(%AdvisoryReference{}, %{type: "WEB", url: at_cap}).valid?

      over_cap = prefix <> combining_string(2001 - byte_size(prefix))
      changeset = AdvisoryReference.changeset(%AdvisoryReference{}, %{type: "WEB", url: over_cap})
      assert errors_on(changeset).url == "should be at most 2000 byte(s)"
    end
  end
end
