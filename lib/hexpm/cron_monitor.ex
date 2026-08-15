defmodule Hexpm.CronMonitor.Sentry do
  @callback capture_check_in(keyword()) :: term()
end

defmodule Hexpm.CronMonitor do
  @moduledoc false

  @spec run(String.t(), String.t(), (-> result)) :: result when result: term()
  def run(slug, schedule, fun) do
    sentry = sentry_impl()
    check_in_id = start_check_in(sentry, slug, schedule)

    outcome =
      try do
        {:ok, fun.()}
      catch
        kind, reason -> {:raised, kind, reason, __STACKTRACE__}
      end

    case outcome do
      {:ok, result} ->
        finish_check_in(sentry, check_in_id, slug, status(result))
        result

      {:raised, kind, reason, stacktrace} ->
        finish_check_in(sentry, check_in_id, slug, :error)
        :erlang.raise(kind, reason, stacktrace)
    end
  end

  defp start_check_in(sentry, slug, schedule) do
    case sentry.capture_check_in(
           status: :in_progress,
           monitor_slug: slug,
           monitor_config: [
             schedule: [type: :crontab, value: schedule],
             timezone: "Etc/UTC"
           ]
         ) do
      {:ok, check_in_id} -> check_in_id
      _other -> nil
    end
  end

  defp finish_check_in(sentry, check_in_id, slug, status) do
    opts = [status: status, monitor_slug: slug]
    opts = if check_in_id, do: [{:check_in_id, check_in_id} | opts], else: opts
    sentry.capture_check_in(opts)
  end

  defp status({:error, _reason}), do: :error
  defp status({:cancel, _reason}), do: :error
  defp status(:error), do: :error
  defp status(_result), do: :ok

  defp sentry_impl(), do: Application.get_env(:hexpm, :sentry_impl) || Sentry
end
