defmodule HexWeb.API.Handlers.Docs do
  import Plug.Conn
  import HexWeb.API.Util
  import HexWeb.Util, only: [api_url: 1, task_start: 1]

  def handle_docs(conn, release, body) do
    case handle_tar(release, body) do
      :ok ->
        package  = release.package
        name     = package.name
        version  = to_string(release.version)

        location = api_url(["packages", name, "releases", version, "docs"])

        conn
        |> put_resp_header("location", location)
        |> cache(:public)
        |> send_resp(201, "")
      {:error, error} ->
        send_validation_failed(conn, [error])
    end
  end

  defp handle_tar(release, body) do
    case :erl_tar.extract({:binary, body}, [:memory, :compressed]) do
      {:ok, files} ->
        files = Enum.map(files, fn {path, data} -> {List.to_string(path), data} end)

        if check_version_dirs?(files) do
          upload_docs(release, files, body) # TODO: Move to supervised task

          :ok
        else
          {:error, {:tar, "directory name not allowed to match a semver version"}}
        end

      {:error, reason} ->
        {:error, {:tar, inspect reason}}
    end
  end

  def upload_docs(release, files, body) do
    package  = release.package
    name     = package.name
    version  = to_string(release.version)

    task_start(fn ->
      store = Application.get_env(:hex_web, :store)

      # Delete old files
      # Add "/" so that we don't get prefix matches, for example phoenix
      # would match phoenix_html
      paths = store.list_docs_pages(name <> "/")
      Enum.each(paths, fn path ->
        first = Path.relative_to(path, name)|> Path.split |> hd
        cond do
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
      Enum.each(files, fn {path, data} ->
        store.put_docs_page(Path.join([name, version, path]), data)
        store.put_docs_page(Path.join(name, path), data)
      end)

      # Set docs flag on release
      %{release | has_docs: true}
      |> HexWeb.Repo.update
    end)
  end

  defp check_version_dirs?(files) do
    Enum.all?(files, fn {path, _data} ->
      first = Path.split(path) |> hd
      Version.parse(first) == :error
    end)
  end
end
