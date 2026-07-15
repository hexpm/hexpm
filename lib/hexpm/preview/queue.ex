defmodule Hexpm.Preview.Queue do
  use Broadway

  alias Hexpm.Preview.Workers

  def start_link(_opts) do
    queue_url = Application.fetch_env!(:hexpm, :preview_queue_id)
    producer = Application.fetch_env!(:hexpm, :preview_queue_producer)
    concurrency = Application.fetch_env!(:hexpm, :preview_queue_concurrency)

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

  defp jobs_for(%{"preview:sitemap" => key}, message_id) when is_binary(key) do
    if Hexpm.Preview.key_components(key) == :error,
      do: {:ok, []},
      else: {:ok, [{Workers.Sitemap, job_args(key, message_id)}]}
  end

  defp jobs_for(data, _message_id), do: {:error, {:unsupported_preview_message, data}}

  defp jobs_for_record(%{"eventName" => "ObjectCreated:" <> _, "s3" => s3}, message_id) do
    job_for_object(Workers.Upload, s3, message_id)
  end

  defp jobs_for_record(%{"eventName" => "ObjectRemoved:" <> _, "s3" => s3}, message_id) do
    job_for_object(Workers.Delete, s3, message_id)
  end

  defp jobs_for_record(record, _message_id), do: {:error, {:unsupported_s3_record, record}}

  defp job_for_object(worker, %{"object" => %{"key" => encoded_key} = object}, message_id) do
    key = URI.decode_www_form(encoded_key)

    if Hexpm.Preview.key_components(key) == :error do
      {:ok, []}
    else
      args = job_args(key, object_generation(object) || message_id)

      {:ok, [{worker, args}]}
    end
  end

  defp job_for_object(_worker, s3, _message_id), do: {:error, {:malformed_s3_object, s3}}

  defp job_args(key, nil), do: %{key: key}
  defp job_args(key, generation), do: %{key: key, generation: generation}

  defp object_generation(object) do
    object["sequencer"] || object["versionId"] || object["eTag"]
  end
end
