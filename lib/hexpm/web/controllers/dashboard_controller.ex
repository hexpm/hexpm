defmodule Hexpm.Web.DashboardController do
  use Hexpm.Web, :controller

  plug :requires_login

  def index(conn, _params) do
    redirect(conn, to: Routes.dashboard_path(conn, :profile))
  end

  def profile(conn, _params) do
    user = conn.assigns.current_user
    render_profile(conn, User.update_profile(user, %{}))
  end

  def update_profile(conn, params) do
    user = conn.assigns.current_user

    case Users.update_profile(user, params["user"], audit: audit_data(conn)) do
      {:ok, _user} ->
        conn
        |> put_flash(:info, "Profile updated successfully.")
        |> redirect(to: Routes.dashboard_path(conn, :profile))
      {:error, changeset} ->
        conn
        |> put_status(400)
        |> render_profile(changeset)
    end
  end

  def password(conn, _params) do
    user = conn.assigns.current_user
    render_password(conn, User.update_password(user, %{}))
  end

  def update_password(conn, params) do
    user = conn.assigns.current_user

    case Users.update_password(user, params["user"], audit: audit_data(conn)) do
      {:ok, _user} ->
        conn
        |> put_flash(:info, "Your password has been updated.")
        |> redirect(to: Routes.dashboard_path(conn, :password))
      {:error, changeset} ->
        conn
        |> put_status(400)
        |> render_password(changeset)
    end
  end

  def email(conn, _params) do
    render_email(conn, conn.assigns.current_user)
  end

  def add_email(conn, %{"email" => email_params}) do
    user = conn.assigns.current_user

    case Users.add_email(user, email_params, audit: audit_data(conn)) do
      {:ok, _user} ->
        email = email_params["email"]
        conn
        |> put_flash(:info, "A verification email has been sent to #{email}.")
        |> redirect(to: Routes.dashboard_path(conn, :email))
      {:error, changeset} ->
        conn
        |> put_status(400)
        |> render_email(user, changeset)
    end
  end

  def remove_email(conn, %{"email" => email} = params) do
    case Users.remove_email(conn.assigns.current_user, params, audit: audit_data(conn)) do
      :ok ->
        conn
        |> put_flash(:info, "Removed email #{email} from your account.")
        |> redirect(to: Routes.dashboard_path(conn, :email))
      {:error, reason} ->
        conn
        |> put_flash(:error, email_error_message(reason, email))
        |> redirect(to: Routes.dashboard_path(conn, :email))
    end
  end

  def primary_email(conn, %{"email" => email} = params) do
    case Users.primary_email(conn.assigns.current_user, params, audit: audit_data(conn)) do
      :ok ->
        conn
        |> put_flash(:info, "Your primary email was changed to #{email}.")
        |> redirect(to: Routes.dashboard_path(conn, :email))
      {:error, reason} ->
        conn
        |> put_flash(:error, email_error_message(reason, email))
        |> redirect(to: Routes.dashboard_path(conn, :email))
    end
  end

  def public_email(conn, %{"email" => email} = params) do
    case Users.public_email(conn.assigns.current_user, params, audit: audit_data(conn)) do
      :ok ->
        conn
        |> put_flash(:info, "Your public email was changed to #{email}.")
        |> redirect(to: Routes.dashboard_path(conn, :email))
      {:error, reason} ->
        conn
        |> put_flash(:error, email_error_message(reason, email))
        |> redirect(to: Routes.dashboard_path(conn, :email))
    end
  end

  def gravatar_email(conn, %{"email" => email} = params) do
    case Users.gravatar_email(conn.assigns.current_user, params, audit: audit_data(conn)) do
      :ok ->
        conn
        |> put_flash(:info, "Your gravatar email was changed to #{email}.")
        |> redirect(to: Routes.dashboard_path(conn, :email))
      {:error, reason} ->
        conn
        |> put_flash(:error, email_error_message(reason, email))
        |> redirect(to: Routes.dashboard_path(conn, :email))
    end
  end

  def resend_verify_email(conn, %{"email" => email} = params) do
    case Users.resend_verify_email(conn.assigns.current_user, params) do
      :ok ->
        conn
        |> put_flash(:info, "A verification email has been sent to #{email}.")
        |> redirect(to: Routes.dashboard_path(conn, :email))
      {:error, reason} ->
        conn
        |> put_flash(:error, email_error_message(reason, email))
        |> redirect(to: Routes.dashboard_path(conn, :email))
    end
  end

  def repository(conn, %{"dashboard_repo" => repository}) do
    access_repository(conn, repository, "read", fn repository ->
      render_repository(conn, repository)
    end)
  end

  def update_repository(conn, %{"dashboard_repo" => repository, "action" => "add_member", "repository_user" => params}) do
    username = params["username"]
    access_repository(conn, repository, "admin", fn repository ->
      case Repositories.add_member(repository, username, params) do
        {:ok, _} ->
          conn
          |> put_flash(:info, "User #{username} has been added to the organization.")
          |> redirect(to: Routes.dashboard_path(conn, :repository, repository))
        {:error, :unknown_user} ->
          conn
          |> put_status(400)
          |> put_flash(:error, "Unknown user #{username}.")
          |> render_repository(repository)
        {:error, changeset} ->
          conn
          |> put_status(400)
          |> render_repository(repository, add_member: changeset)
      end
    end)
  end

  def update_repository(conn, %{"dashboard_repo" => repository, "action" => "remove_member", "repository_user" => params}) do
    # TODO: Also remove all package ownerships on repository for removed member
    username = params["username"]
    access_repository(conn, repository, "admin", fn repository ->
      case Repositories.remove_member(repository, username) do
        :ok ->
          conn
          |> put_flash(:info, "User #{username} has been removed from the repository.")
          |> redirect(to: Routes.dashboard_path(conn, :repository, repository))
        {:error, reason} ->
          conn
          |> put_status(400)
          |> put_flash(:error, remove_member_error_message(reason, username))
          |> render_repository(repository)
      end
    end)
  end

  def update_repository(conn, %{"dashboard_repo" => repository, "action" => "change_role", "repository_user" => params}) do
    username = params["username"]
    access_repository(conn, repository, "admin", fn repository ->
      case Repositories.change_role(repository, username, params) do
        {:ok, _} ->
          conn
          |> put_flash(:info, "User #{username}'s role has been changed to #{params["role"]}.")
          |> redirect(to: Routes.dashboard_path(conn, :repository, repository))
        {:error, :unknown_user} ->
          conn
          |> put_status(400)
          |> put_flash(:error, "Unknown user #{username}.")
          |> render_repository(repository)
        {:error, :last_admin} ->
          conn
          |> put_status(400)
          |> put_flash(:error, "Cannot demote last admin member.")
          |> render_repository(repository)
        {:error, changeset} ->
          conn
          |> put_status(400)
          |> render_repository(repository, change_role: changeset)
      end
    end)
  end

  def repository_signup(conn, _params) do
    render conn, "repository_signup.html", [
      title: "Dashboard - Repository sign up",
      container: "container page dashboard",
    ]
  end

  def new_repository_signup(conn, %{"name" => name, "members" => members, "opensource" => opensource}) do
    Emails.repository_signup(conn.assigns.current_user, name, members, opensource)
    |> Mailer.deliver_now_throttled()

    conn
    |> put_flash(:info, "You have requested access to the organization beta. We will get back to you shortly.")
    |> redirect(to: Routes.dashboard_path(conn, :repository_signup))
  end

  defp render_profile(conn, changeset) do
    render conn, "profile.html", [
      title: "Dashboard - Public profile",
      container: "container page dashboard",
      changeset: changeset
    ]
  end

  defp render_password(conn, changeset) do
    render conn, "password.html", [
      title: "Dashboard - Change password",
      container: "container page dashboard",
      changeset: changeset
    ]
  end

  defp render_email(conn, user, add_email_changeset \\ add_email_changeset()) do
    emails = Email.order_emails(user.emails)

    render conn, "email.html", [
      title: "Dashboard - Email",
      container: "container page dashboard",
      add_email_changeset: add_email_changeset,
      emails: emails
    ]
  end

  defp render_repository(conn, repository, opts \\ []) do
    render conn, "repository.html", [
      title: "Dashboard - Repository",
      container: "container page dashboard",
      repository: repository,
      add_member_changeset: opts[:add_member_changeset] || add_member_changeset(),
    ]
  end

  defp access_repository(conn, repository, role, fun) do
    user = conn.assigns.current_user
    repository = Repositories.get(repository, [:packages, :repository_users, users: :emails])
    if repository do
      if repo_user = Enum.find(repository.repository_users, &(&1.user_id == user.id)) do
        if repo_user.role in Repository.role_or_higher(role) do
          fun.(repository)
        else
          conn
          |> put_status(400)
          |> put_flash(:error, "You do not have permission for this action.")
          |> render_repository(repository)
        end
      else
        not_found(conn)
      end
    else
      not_found(conn)
    end
  end

  defp add_email_changeset() do
    Email.changeset(%Email{}, :create, %{}, false)
  end

  defp add_member_changeset() do
    Repository.add_member(%RepositoryUser{}, %{})
  end

  defp email_error_message(:unknown_email, email), do: "Unknown email #{email}."
  defp email_error_message(:not_verified, email), do: "Email #{email} not verified."
  defp email_error_message(:already_verified, email), do: "Email #{email} already verified."
  defp email_error_message(:primary, email), do: "Cannot remove primary email #{email}."

  defp remove_member_error_message(:unknown_user, username), do: "Unknown user #{username}."
  defp remove_member_error_message(:last_member, _username), do: "Cannot remove last member from organization."
end
