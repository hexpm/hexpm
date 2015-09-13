defmodule HexWeb.API.Handlers.Docs do
  import Plug.Conn
  import HexWeb.API.Util
  import HexWeb.Util, only: [api_url: 1, task: 3]

  def publish(conn, release, user, body) do
    case handle_tar(release, user, body) do
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

  defp handle_tar(release, user, body) do
    case :erl_tar.extract({:binary, body}, [:memory, :compressed]) do
      {:ok, files} ->
        files = Enum.map(files, fn {path, data} -> {List.to_string(path), data} end)

        if check_version_dirs?(files) do
          task    = fn -> upload_docs(release, files, body) end
          success = fn -> success(release, user) end
          failure = fn -> failure(release, user) end
          task(task, success, failure)

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

    store = Application.get_env(:hex_web, :store)

    files =
      Enum.flat_map(files, fn {path, data} ->
        [{Path.join([name, version, path]), data},
         {Path.join(name, path), data}]
      end)

    paths = Enum.into(files, HashSet.new, &elem(&1, 0))

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
    Enum.each(files, fn {path, data} -> store.put_docs_page(path, data) end)

    # Set docs flag on release
    %{release | has_docs: true}
    |> HexWeb.Repo.update
  end

  defp check_version_dirs?(files) do
    Enum.all?(files, fn {path, _data} ->
      first = Path.split(path) |> hd
      Version.parse(first) == :error
    end)
  end

  defp success(release, user) do
    package = release.package.name
    version = to_string(release.version)
    email   = Application.get_env(:hex_web, :email)
    body    = HexWeb.Email.Templates.render(:publish_success,
                                            package: package,
                                            version: version,
                                            docs: true)
    title   = "Hex.pm - Documentation for #{package} v#{version} has been published"
    email.send(user.email, title, body)
  end

  defp failure(release, user) do
    # TODO: Revert database changes
    package = release.package.name
    version = to_string(release.version)
    email   = Application.get_env(:hex_web, :email)
    body    = HexWeb.Email.Templates.render(:publish_fail,
                                            package: package,
                                            version: version,
                                            docs: true)
    title   = "Hex.pm - Documentation for #{package} v#{version} failed to publish succesfully"
    email.send(user.email, title, body)
  end

  def revert(name, release) do
    task = fn ->
      version = to_string(release.version)
      store   = Application.get_env(:hex_web, :store)
      paths   = store.list_docs_pages(Path.join(name, version))
      store.delete_docs("#{name}-#{version}.tar.gz")

      Enum.each(paths, fn path ->
        store.delete_docs_page(path)
      end)

      %{release | has_docs: false}
      |> HexWeb.Repo.update
    end

    # TODO: Send mails
    task(task, fn -> end, fn -> end)
  end
end
