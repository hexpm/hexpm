defmodule Hexpm.Hexdocs.Queue do
  use Broadway

  alias Hexpm.Hexdocs.Workers

  def start_link(_opts) do
    queue_url = Application.fetch_env!(:hexpm, :hexdocs_queue_id)
    producer = Application.fetch_env!(:hexpm, :hexdocs_queue_producer)
    concurrency = Application.fetch_env!(:hexpm, :hexdocs_queue_concurrency)

    Broadway.start_link(__MODULE__,
      name: __MODULE__,
      producer: [
        module: {
          producer,
          queue_url: queue_url,
          max_number_of_messages: concurrency,
          wait_time_seconds: 10,
          visibility_timeout: 300
        },
        concurrency: 1
      ],
      processors: [default: [concurrency: concurrency, min_demand: 0, max_demand: 1]]
    )
  end

  @impl Broadway
  def handle_message(_processor, %Broadway.Message{} = message, _context) do
    with {:ok, data} <- Jason.decode(message.data),
         {:ok, jobs} <- jobs_for(data),
         {:ok, _inserted} <- insert_jobs(jobs) do
      message
    else
      {:error, reason} -> Broadway.Message.failed(message, reason)
    end
  rescue
    exception -> Broadway.Message.failed(message, exception)
  end

  defp insert_jobs(jobs) do
    Hexpm.Repo.transaction(fn ->
      Enum.map(jobs, fn {worker, key} ->
        key
        |> then(&worker.new(%{key: &1}))
        |> Oban.insert!()
      end)
    end)
  end

  defp jobs_for(%{"Event" => "s3:TestEvent"}), do: {:ok, []}

  defp jobs_for(%{"Records" => records}) when is_list(records) do
    Enum.reduce_while(records, {:ok, []}, fn record, {:ok, jobs} ->
      case jobs_for_record(record) do
        {:ok, record_jobs} -> {:cont, {:ok, jobs ++ record_jobs}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp jobs_for(%{"hexdocs:upload" => key}) when is_binary(key),
    do: {:ok, [{Workers.Upload, key}]}

  defp jobs_for(%{"hexdocs:search" => key}) when is_binary(key),
    do: {:ok, [{Workers.Search, key}]}

  defp jobs_for(%{"hexdocs:sitemap" => key}) when is_binary(key),
    do: {:ok, [{Workers.Sitemap, key}]}

  defp jobs_for(data), do: {:error, {:unsupported_hexdocs_message, data}}

  defp jobs_for_record(%{"eventName" => "ObjectCreated:" <> _, "s3" => s3}) do
    key = decode_s3_key(s3)

    case Hexpm.Hexdocs.key_components(key) do
      {:ok, "hexpm", _package, _version} -> {:ok, [{Workers.Upload, key}, {Workers.Search, key}]}
      {:ok, _repository, _package, _version} -> {:ok, [{Workers.Upload, key}]}
      :error -> {:ok, []}
    end
  end

  defp jobs_for_record(%{"eventName" => "ObjectRemoved:" <> _, "s3" => s3}) do
    key = decode_s3_key(s3)

    if Hexpm.Hexdocs.key_components(key) == :error,
      do: {:ok, []},
      else: {:ok, [{Workers.Delete, key}]}
  end

  defp jobs_for_record(record), do: {:error, {:unsupported_s3_record, record}}

  defp decode_s3_key(%{"object" => %{"key" => key}}), do: URI.decode_www_form(key)
end
