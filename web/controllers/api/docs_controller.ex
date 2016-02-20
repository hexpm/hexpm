defmodule HexWeb.API.DocsController do
  use HexWeb.Web, :controller

  @zlib_magic 16 + 15
  @compressed_max_size 8 * 1024 * 1024
  @uncompressed_max_size 64 * 1024 * 1024

  plug :fetch_release
  plug :authorize, [fun: &package_owner?/2] when action != :show

  def show(conn, _params) do
    package = conn.assigns.package
    release = conn.assigns.release

    if release.has_docs do
      redirect(conn, external: HexWeb.Utils.docs_tarball_url(package, release))
    else
      not_found(conn)
    end
  end

  def create(conn, %{"body" => body}) do
    package = conn.assigns.package
    release = conn.assigns.release
    user    = conn.assigns.user
    handle_tarball(conn, package, release, user, body)
  end

  def delete(conn, _params) do
    revert(conn.assigns.release)

    conn
    |> api_cache(:private)
    |> send_resp(204, "")
  end

  defp handle_tarball(conn, package, release, user, body) do
    case parse_tarball(package, release, user, body) do
      :ok ->
        location = HexWeb.Utils.docs_tarball_url(package, release)

        conn
        |> put_resp_header("location", location)
        |> api_cache(:public)
        |> send_resp(201, "")
      {:error, error} ->
        validation_failed(conn, error)
    end
  end

  defp parse_tarball(package, release, user, body) do
    case unzip(body) do
      {:ok, data} ->
        case :erl_tar.extract({:binary, data}, [:memory]) do
          {:ok, files} ->
            files = Enum.map(files, fn {path, data} -> {List.to_string(path), data} end)

            if check_version_dirs?(files) do
              task    = fn -> upload_docs(package, release, files, body) end
              success = fn -> :ok end
              failure = fn reason -> failure(package, release, user, reason) end
              HexWeb.Utils.task(task, success, failure)

              :ok
            else
              {:error, [tar: "directory name not allowed to match a semver version"]}
            end

          {:error, reason} ->
            {:error, [tar: inspect reason]}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp unzip(data) when byte_size(data) > @compressed_max_size do
    {:error, [tar: :too_big]}
  end

  defp unzip(data) do
    stream = :zlib.open

    try do
      :zlib.inflateInit(stream, @zlib_magic)
      # limit single uncompressed chunk size to 512kb
      :zlib.setBufSize(stream, 512 * 1024)
      uncompressed = unzip_inflate(stream, "", 0, :zlib.inflateChunk(stream, data))
      :zlib.inflateEnd(stream)
      uncompressed
    after
      :zlib.close(stream)
    end
  end

  defp unzip_inflate(_stream, _data, total, _) when total > @uncompressed_max_size do
    {:error, [tar: :too_big]}
  end

  defp unzip_inflate(stream, data, total, {:more, uncompressed}) do
    total = total + byte_size(uncompressed)
    unzip_inflate(stream, [data|uncompressed], total, :zlib.inflateChunk(stream))
  end

  defp unzip_inflate(_stream, data, _total, uncompressed) do
    {:ok, IO.iodata_to_binary([data|uncompressed])}
  end

  def upload_docs(package, release, files, body) do
    name     = package.name
    version  = to_string(release.version)

    store = Application.get_env(:hex_web, :store)

    unversioned_key = "docspage/#{package.name}"
    versioned_key = "docspage/#{package.name}/#{release.version}"

    files =
      Enum.flat_map(files, fn {path, data} ->
        [{Path.join([name, version, path]), versioned_key, data},
         {Path.join(name, path), unversioned_key, data}]
      end)

    paths = Enum.into(files, MapSet.new, &elem(&1, 0))

    # Delete old files
    # Add "/" so that we don't get prefix matches, for example phoenix
    # would match phoenix_html
    existing_paths = store.list_docs_pages("#{name}/")
    Enum.each(existing_paths, fn path ->
      first = Path.relative_to(path, name) |> Path.split |> hd
      cond do
        # Don't delete if we are going to overwrite with new files, this
        # removes the downtime between a deleted and added page
        path in paths ->
          :ok
        # Current (/ecto/0.8.1/...)
        first == version ->
          store.delete_docs_page(path)
        # Top-level docs, don't match version directories (/ecto/...)
        Version.parse(first) == :error ->
          store.delete_docs_page(path)
        true ->
          :ok
      end
    end)

    # Put tarball
    store.put_docs("#{name}-#{version}.tar.gz", body)

    # Upload new files
    Enum.each(files, fn {path, key, data} -> store.put_docs_page(path, key, data) end)

    # Set docs flag on release
    Ecto.Changeset.change(release, has_docs: true)
    |> HexWeb.Repo.update!
  end

  defp check_version_dirs?(files) do
    Enum.all?(files, fn {path, _data} ->
      first = Path.split(path) |> hd
      Version.parse(first) == :error
    end)
  end

  defp failure(package, release, user, reason) do
    require Logger
    Logger.error "Package upload failed: #{inspect reason}"

    # TODO: Revert database changes

    HexWeb.Mailer.send(
      "publish_fail.html",
      "Hex.pm - ERROR when publishing documentation for #{package.name} v#{release.version}",
      user.email,
      package: package.name,
      version: release.version,
      docs: true)
  end

  def revert(release) do
    task = fn ->
      name    = release.package.name
      version = to_string(release.version)
      store   = Application.get_env(:hex_web, :store)
      paths   = store.list_docs_pages(Path.join(name, version))

      store.delete_docs("#{name}-#{version}.tar.gz")

      Enum.each(paths, fn path ->
        store.delete_docs_page(path)
      end)

      Ecto.Changeset.change(release, has_docs: false)
      |> HexWeb.Repo.update!
    end

    # TODO: Send mails
    HexWeb.Utils.task(task, fn -> nil end, fn _ -> nil end)
  end
end
