defmodule Hexpm.PromEx.Plugins.EmailTest do
  use ExUnit.Case, async: true

  alias Hexpm.PromEx.Plugins.Email, as: Plugin

  defp metadata(private, extra \\ %{}) do
    Map.merge(%{email: %Swoosh.Email{private: private}, mailer: Hexpm.Emails.Mailer}, extra)
  end

  test "tags a delivery by the builder's type and the outcome" do
    tags = Plugin.deliver_tags(metadata(%{type: "announcement"}, %{result: %{id: "sg-1"}}))
    assert tags == %{type: "announcement", outcome: "ok"}
  end

  test "labels a refusal with the provider's status and a failure without one as an error" do
    refused = metadata(%{type: "verification"}, %{error: {429, %{"errors" => []}}})
    assert Plugin.deliver_tags(refused).outcome == "429"

    failed = metadata(%{type: "verification"}, %{error: :timeout})
    assert Plugin.deliver_tags(failed).outcome == "error"
  end

  test "counts a mail without a type rather than dropping it" do
    assert Plugin.type_tags(metadata(%{})) == %{type: "untyped"}
  end

  test "attaches to the Swoosh delivery events" do
    events =
      [otp_app: :hexpm]
      |> Plugin.event_metrics()
      |> List.wrap()
      |> Enum.flat_map(& &1.metrics)
      |> Enum.map(& &1.event_name)
      |> Enum.uniq()

    assert events == [[:swoosh, :deliver, :stop], [:swoosh, :deliver, :exception]]
  end
end
