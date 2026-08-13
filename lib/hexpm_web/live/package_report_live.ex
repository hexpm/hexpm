defmodule HexpmWeb.PackageReportLive do
  use HexpmWeb, :live_view

  alias Hexpm.Accounts.User
  alias Hexpm.PackageReports
  alias Hexpm.PackageReports.Report
  alias HexpmWeb.Captcha
  alias HexpmWeb.RepositoryAccess

  defmodule NotFoundError do
    defexception message: "Package not found", plug_status: 404
  end

  @impl true
  def mount(params, _session, socket) do
    repository = params["repository"] || "hexpm"
    package_name = params["name"]
    return_path = report_path(repository, package_name)

    case socket.assigns.current_user do
      nil ->
        {:ok, redirect(socket, to: ~p"/login?#{[return: return_path]}")}

      %User{} ->
        case RepositoryAccess.fetch_package(
               socket.assigns.current_user,
               repository,
               package_name
             ) do
          {:ok, package} ->
            {:ok,
             assign(socket,
               package: package,
               package_identifier: PackageReports.package_identifier(package),
               package_path: PackageReports.package_path(package),
               form: new_form(),
               result: nil,
               captcha_error: nil,
               page_title: "Report #{PackageReports.package_identifier(package)} | Hex",
               container: "container"
             )}

          :error ->
            raise NotFoundError
        end
    end
  end

  @impl true
  def handle_event("validate", %{"report" => params}, socket) do
    form =
      %Report{}
      |> Report.changeset(params)
      |> Map.put(:action, :validate)
      |> to_form(as: :report)

    {:noreply, assign(socket, form: form)}
  end

  @impl true
  def handle_event("submit", %{"report" => params} = event_params, socket) do
    changeset = Report.changeset(%Report{}, params)
    submitted_form = changeset |> Map.put(:action, :validate) |> to_form(as: :report)

    if changeset.valid? do
      submit_report(event_params["h-captcha-response"], params, submitted_form, socket)
    else
      {:noreply, assign(socket, form: submitted_form, captcha_error: nil)}
    end
  end

  defp submit_report(captcha_token, params, submitted_form, socket) do
    if Captcha.verify(captcha_token) do
      deliver_report(params, submitted_form, assign(socket, captcha_error: nil))
    else
      {:noreply,
       socket
       |> assign(
         form: submitted_form,
         captcha_error: "Please complete the captcha to submit a package report."
       )
       |> push_event("reset-hcaptcha", %{})}
    end
  end

  defp deliver_report(params, submitted_form, socket) do
    case PackageReports.submit(socket.assigns.package, socket.assigns.current_user, params) do
      {:ok, %{sign_in_url: sign_in_url}} ->
        {:noreply, assign(socket, result: %{kind: :vulnerability, url: sign_in_url})}

      {:ok, :email} ->
        {:noreply, assign(socket, result: %{kind: :email})}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, form: to_form(changeset, as: :report))}

      {:error, :unverified_primary_email} ->
        {:noreply,
         socket
         |> assign(form: submitted_form)
         |> put_flash(
           :error,
           "A verified primary email address is required to submit a package report."
         )
         |> push_event("reset-hcaptcha", %{})}

      {:error, :unavailable} ->
        {:noreply,
         socket
         |> assign(form: submitted_form)
         |> put_flash(:error, "The report couldn't be submitted. Please try again later.")
         |> push_event("reset-hcaptcha", %{})}
    end
  end

  defp new_form do
    %Report{}
    |> Report.changeset(%{"reason" => "vulnerability"})
    |> to_form(as: :report)
  end

  defp report_path("hexpm", package), do: "/packages/#{package}/report"
  defp report_path(repository, package), do: "/packages/#{repository}/#{package}/report"
end
