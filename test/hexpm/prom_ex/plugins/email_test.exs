defmodule Hexpm.PromEx.Plugins.EmailTest do
  use ExUnit.Case, async: true

  alias Hexpm.PromEx.Plugins.Email, as: Plugin

  defp metadata(private, extra \\ %{}) do
    Map.merge(%{email: %Swoosh.Email{private: private}, mailer: Hexpm.Emails.Mailer}, extra)
  end

  test "reports a delivery by the builder's type and the outcome" do
    ref =
      :telemetry_test.attach_event_handlers(self(), [
        [:hexpm, :email, :deliver, :done],
        [:hexpm, :email, :deliver, :raised]
      ])

    on_exit(fn -> :telemetry.detach(ref) end)

    Plugin.delivered(metadata(%{type: "announcement"}, %{result: %{id: "sg-1"}}))

    assert_received {[:hexpm, :email, :deliver, :done], ^ref, %{count: 1},
                     %{type: "announcement", outcome: "ok"}}

    Plugin.raised(metadata(%{type: "announcement"}, %{kind: :error, reason: :closed}))

    assert_received {[:hexpm, :email, :deliver, :raised], ^ref, %{count: 1},
                     %{type: "announcement"}}
  end

  test "labels a refusal with the provider's status and a failure without one as an error" do
    refused = metadata(%{type: "verification"}, %{error: {429, %{"errors" => []}}})
    assert Plugin.outcome(refused) == "429"

    failed = metadata(%{type: "verification"}, %{error: :timeout})
    assert Plugin.outcome(failed) == "error"
  end

  test "counts a mail without a type rather than dropping it" do
    assert Plugin.type_tags(metadata(%{})) == %{type: "untyped"}
  end

  test "counts deliveries on events of their own and times them on Swoosh's" do
    events =
      [otp_app: :hexpm]
      |> Plugin.event_metrics()
      |> List.wrap()
      |> Map.new(&{&1.group_name, &1.metrics})
      |> Map.fetch!(:hexpm_email_event_metrics)
      |> Map.new(&{&1.name, &1.event_name})

    assert events == %{
             [:hexpm, :prom_ex, :email, :deliver, :total] => [:hexpm, :email, :deliver, :done],
             [:hexpm, :prom_ex, :email, :deliver, :duration, :milliseconds] => [
               :swoosh,
               :deliver,
               :stop
             ],
             [:hexpm, :prom_ex, :email, :deliver, :exception, :total] => [
               :hexpm,
               :email,
               :deliver,
               :raised
             ]
           }
  end
end
