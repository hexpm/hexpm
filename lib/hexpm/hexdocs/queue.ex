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
    with {:ok, data} <- JSON.decode(message.data),
         {:ok, jobs} <- jobs_for(data, message.metadata[:message_id]),
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
      Enum.map(jobs, fn {worker, args} ->
        args
        |> worker.new()
        |> Oban.insert!()
      end)
    end)
  end

  defp jobs_for(%{"Event" => "s3:TestEvent"}, _message_id), do: {:ok, []}

  defp jobs_for(%{"Records" => records}, message_id) when is_list(records) do
    Enum.reduce_while(records, {:ok, []}, fn record, {:ok, jobs} ->
      case jobs_for_record(record, message_id) do
        {:ok, record_jobs} -> {:cont, {:ok, jobs ++ record_jobs}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp jobs_for(%{"hexdocs:upload" => key}, _message_id) when is_binary(key),
    do: {:ok, [{Workers.Upload, %{key: key}}]}

  defp jobs_for(%{"hexdocs:search" => key}, _message_id) when is_binary(key),
    do: {:ok, [{Workers.Search, %{key: key}}]}

  defp jobs_for(%{"hexdocs:sitemap" => key}, _message_id) when is_binary(key),
    do: {:ok, [{Workers.Sitemap, %{key: key}}]}

  defp jobs_for(data, _message_id), do: {:error, {:unsupported_hexdocs_message, data}}

  defp jobs_for_record(%{"eventName" => "ObjectCreated:" <> _, "s3" => s3}, message_id) do
    jobs_for_object(s3, message_id, &created_workers/1)
  end

  defp jobs_for_record(%{"eventName" => "ObjectRemoved:" <> _, "s3" => s3}, message_id) do
    jobs_for_object(s3, message_id, &removed_workers/1)
  end

  defp jobs_for_record(record, _message_id), do: {:error, {:unsupported_s3_record, record}}

  defp created_workers("hexpm"), do: [Workers.Upload, Workers.Search]
  defp created_workers(_repository), do: [Workers.Upload]

  defp removed_workers(_repository), do: [Workers.Delete]

  defp jobs_for_object(%{"object" => %{"key" => encoded_key} = object}, message_id, workers) do
    key = URI.decode_www_form(encoded_key)

    case Hexpm.Hexdocs.key_components(key) do
      {:ok, repository, _package, _version} ->
        args = job_args(key, object_generation(object) || message_id)
        {:ok, Enum.map(workers.(repository), &{&1, args})}

      :error ->
        {:ok, []}
    end
  end

  defp jobs_for_object(s3, _message_id, _workers), do: {:error, {:malformed_s3_object, s3}}

  defp job_args(key, nil), do: %{key: key}
  defp job_args(key, generation), do: %{key: key, generation: generation}

  defp object_generation(object) do
    object["sequencer"] || object["versionId"] || object["eTag"]
  end
end
