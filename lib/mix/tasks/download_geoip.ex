defmodule Mix.Tasks.DownloadGeoip do
  @moduledoc """
  Downloads the free DB-IP IP-to-Country Lite database used for audit-log IP
  geolocation and writes it as an MMDB file (default `priv/geoip/country.mmdb`).

  Usage:
      mix download_geoip [--output PATH] [--month YYYY-MM]

  Then point Hexpm at it:
      export HEXPM_GEOIP_COUNTRY_PATH=priv/geoip/country.mmdb

  The current month is used by default. If that month's file has not been
  published yet (DB-IP releases in the first few days), the previous month is
  tried automatically. Pass `--month` to pin a specific release.

  Data: DB-IP IP-to-Country Lite (https://db-ip.com), licensed CC BY 4.0.
  """
  use Mix.Task

  @shortdoc "Download the DB-IP IP-to-Country Lite database for geolocation"

  @default_output "priv/geoip/country.mmdb"
  @base_url "https://download.db-ip.com/free"

  @impl Mix.Task
  def run(args) do
    {opts, _, _} = OptionParser.parse(args, strict: [output: :string, month: :string])
    output = opts[:output] || @default_output
    month = opts[:month] || Calendar.strftime(Date.utc_today(), "%Y-%m")
    explicit_month? = !!opts[:month]

    {:ok, _} = Application.ensure_all_started(:req)

    download(month, output, explicit_month?)
  end

  defp download(month, output, explicit_month?) do
    url = "#{@base_url}/dbip-country-lite-#{month}.mmdb.gz"
    Mix.shell().info("Downloading #{url} ...")

    # Bounded timeouts so a stalled connection fails the build instead of
    # hanging indefinitely.
    case Req.get(url, connect_options: [timeout: 30_000], receive_timeout: 120_000) do
      {:ok, %{status: 200, body: body}} ->
        write(body, output)

      {:ok, %{status: 404}} when not explicit_month? ->
        prev = previous_month(month)

        Mix.shell().info("#{month} not published yet — falling back to #{prev}.")

        download(prev, output, true)

      {:ok, %{status: 404}} ->
        Mix.raise("Not found (404): #{url}")

      {:ok, %{status: status}} ->
        Mix.raise("Download failed (HTTP #{status}): #{url}")

      {:error, reason} ->
        Mix.raise("Download failed: #{inspect(reason)}")
    end
  end

  defp write(body, output) do
    # Req transparently decompresses responses sent with `content-encoding:
    # gzip`, so the body may already be the plain MMDB. Only gunzip if it
    # still carries the gzip magic bytes.
    mmdb =
      case body do
        <<0x1F, 0x8B, _::binary>> -> :zlib.gunzip(body)
        plain -> plain
      end

    File.mkdir_p!(Path.dirname(output))
    File.write!(output, mmdb)

    Mix.shell().info("Wrote #{output} (#{Float.round(byte_size(mmdb) / 1_048_576, 1)} MB).")
    Mix.shell().info("Set HEXPM_GEOIP_COUNTRY_PATH=#{output} to enable geolocation.")
  end

  defp previous_month(month) do
    [year, mon] = month |> String.split("-") |> Enum.map(&String.to_integer/1)
    {year, mon} = if mon == 1, do: {year - 1, 12}, else: {year, mon - 1}
    "#{year}-#{String.pad_leading(to_string(mon), 2, "0")}"
  end
end
